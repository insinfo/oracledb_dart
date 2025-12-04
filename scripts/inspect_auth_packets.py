from diff_packets import parse_dart, parse_python


def read_ub4(data: bytes, pos: int) -> tuple[int, int]:
    length = data[pos]
    pos += 1
    if length == 0:
        return 0, pos
    if length == 1:
        return data[pos], pos + 1
    if length == 2:
        value = int.from_bytes(data[pos : pos + 2], "big")
        return value, pos + 2
    if length == 4:
        value = int.from_bytes(data[pos : pos + 4], "big")
        return value, pos + 4
    raise ValueError(f"unsupported UB4 length prefix {length}")


def read_bytes_with_length(data: bytes, pos: int) -> tuple[bytes, int]:
    length = data[pos]
    pos += 1
    if length == 0:
        return b"", pos
    if length != 0xFE:
        return data[pos : pos + length], pos + length
    # long form
    chunks = bytearray()
    while True:
        chunk_len = int.from_bytes(data[pos : pos + 4], "big")
        pos += 4
        if chunk_len == 0:
            break
        chunks.extend(data[pos : pos + chunk_len])
        pos += chunk_len
    return bytes(chunks), pos


def dump_auth_fields(packet: bytes) -> dict:
    pos = 8  # skip TNS header
    pos += 2  # data flags
    msg_type = packet[pos]
    func_code = packet[pos + 1]
    seq_num = packet[pos + 2]
    pos += 3
    payload = {
        "msg_type": msg_type,
        "function": func_code,
        "seq": seq_num,
    }
    has_user = packet[pos]
    pos += 1
    user_len, pos = read_ub4(packet, pos)
    auth_mode, pos = read_ub4(packet, pos)
    pos += 1  # pointer (authivl)
    num_pairs, pos = read_ub4(packet, pos)
    pos += 2  # authovl pointers
    if has_user:
        user_bytes, pos = read_bytes_with_length(packet, pos)
        payload["user"] = user_bytes.decode()
    payload["auth_mode"] = auth_mode
    payload["num_pairs"] = num_pairs
    pairs = []
    for _ in range(num_pairs):
        key_len, pos = read_ub4(packet, pos)
        key_bytes, pos = read_bytes_with_length(packet, pos)
        value_len, pos = read_ub4(packet, pos)
        value_bytes, pos = read_bytes_with_length(packet, pos)
        flags, pos = read_ub4(packet, pos)
        pairs.append(
            {
                "key": key_bytes.decode(),
                "value_len": value_len,
                "value": value_bytes.decode(errors="ignore"),
                "flags": flags,
            }
        )
    payload["pairs"] = pairs
    return payload


def main():
    dart_packets = parse_dart("auth_dart_packets.log")
    py_packets = parse_python("auth_python_packets.log")

    dart = dump_auth_fields(dart_packets["auth-phase1"])
    py = dump_auth_fields(py_packets["op9"])

    print(
        f"Dart AUTH phase1: auth_mode={dart['auth_mode']} num_pairs={dart['num_pairs']}"
    )
    for pair in dart["pairs"]:
        print(f"  {pair['key']}: {pair['value']} (len={pair['value_len']})")

    print(
        f"\nPython AUTH phase1: auth_mode={py['auth_mode']} num_pairs={py['num_pairs']}"
    )
    for pair in py["pairs"]:
        print(f"  {pair['key']}: {pair['value']} (len={pair['value_len']})")


if __name__ == "__main__":
    main()
