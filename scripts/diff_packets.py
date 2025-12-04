import re
from pathlib import Path

def parse_dart(path):
    blocks = {}
    current = None
    data = []
    for line in Path(path).read_text().splitlines():
        if line.startswith('[') and 'SEND' in line:
            if current and data:
                hexstr = ''.join(data).replace(' ', '')
                blocks[current] = bytes.fromhex(hexstr)
            parts = line.split('] ')[1].split()
            # e.g. 'SEND auth-phase1 len=...' -> use message label
            current = parts[1]
            data = []
        elif re.match(r'^[0-9a-f]{4}:', line):
            hexpart = line.split(':', 1)[1].strip().split('  ')[0]
            data.append(hexpart)
    if current and data:
        blocks[current] = bytes.fromhex(''.join(data).replace(' ', ''))
    return blocks


def parse_python(path):
    blocks = {}
    lines = Path(path).read_text().splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        if 'Sending packet' in line:
            label = f"op{line.split('[op ')[1].split(']')[0]}"
            i += 1
            data = []
            while i < len(lines) and re.match(r'^[0-9A-F]{4} :', lines[i]):
                hexpart = lines[i].split('|')[0].split(':')[1].strip()
                data.append(hexpart)
                i += 1
            blocks[label] = bytes.fromhex(''.join(data).replace(' ', ''))
        else:
            i += 1
    return blocks


def diff_sequences(name_a, seq_a, name_b, seq_b):
    print(f"Comparando {name_a} ({len(seq_a)} bytes) vs {name_b} ({len(seq_b)} bytes)")
    for idx, (ba, bb) in enumerate(zip(seq_a, seq_b)):
        if ba != bb:
            print(f"Primeira divergencia no offset {idx:#04x}: {ba:#04x} (A) vs {bb:#04x} (B)")
            break
    if len(seq_a) != len(seq_b):
        print(f"Uma sequencia é sufixo da outra; diferença inicia no offset {min(len(seq_a), len(seq_b)):#04x}")
    else:
        print("Sequencias idênticas")
    # Also compare desconsiderando cabeçalho TNS de 4 bytes
    payload_a = seq_a[4:]
    payload_b = seq_b[4:]
    for idx, (ba, bb) in enumerate(zip(payload_a, payload_b)):
        if ba != bb:
            print(f"Diferença no payload offset {idx:#04x} (após cabeçalho): {ba:#04x} vs {bb:#04x}")
            break


def main():
    dart = parse_dart('auth_dart_packets.log')
    py = parse_python('auth_python_packets.log')
    diff_sequences('dart auth-phase1', dart['auth-phase1'], 'python op9 (auth phase1)', py['op9'])
    diff_sequences('dart auth-phase2', dart.get('auth-phase2', b''), 'python op11 (auth phase2)', py['op11'])


if __name__ == '__main__':
    main()
