# Equivalent of benchmark/bench.dart for python-oracledb (thin mode), using
# the same protocol as package:benchmark_harness: setup, warm up for at least
# 100 ms, measure for at least 2 s and report the mean time per run (the
# median of 3 measurements is reported).
#
#   pip install oracledb
#   python benchmark/bench.py

import datetime
import os
import statistics
import time

import oracledb

USER = os.environ.get("ORACLE_USER", "dart_user")
PASSWORD = os.environ.get("ORACLE_PASSWORD", "dart")
DSN = os.environ.get("ORACLE_DSN", "localhost:1521/FREEPDB1")

sink = None


def connect():
    return oracledb.connect(user=USER, password=PASSWORD, dsn=DSN)


def measure_for(fn, minimum_millis):
    minimum = minimum_millis / 1000
    start = time.perf_counter()
    iterations = 0
    elapsed = 0.0
    while elapsed < minimum:
        fn()
        elapsed = time.perf_counter() - start
        iterations += 1
    return elapsed * 1e6 / iterations


class Benchmark:
    name = ""
    units = 1

    def setup(self):
        self.conn = connect()

    def teardown(self):
        self.conn.close()

    def run(self):
        raise NotImplementedError

    def measure(self):
        self.setup()
        try:
            measure_for(self.run, 100)
            return measure_for(self.run, 2000)
        finally:
            self.teardown()


class ConnectBenchmark(Benchmark):
    name = "connect + close"

    def setup(self):
        pass

    def teardown(self):
        pass

    def run(self):
        global sink
        conn = connect()
        sink = conn.session_id if hasattr(conn, "session_id") else conn
        conn.close()


class PingBenchmark(Benchmark):
    name = "ping (round trip)"

    def run(self):
        self.conn.ping()


class QueryWithBindBenchmark(Benchmark):
    name = "query with bind (1 row)"

    def setup(self):
        super().setup()
        self.cursor = self.conn.cursor()
        self.i = 0

    def run(self):
        global sink
        self.cursor.execute("select :1 + 1 from dual", [self.i])
        self.i += 1
        sink = self.cursor.fetchone()


class FetchBenchmark(Benchmark):
    name = "fetch 100k rows x 4 cols"
    units = 100000
    sql = (
        "select level, 'name ' || level, "
        "date '2020-01-01' + mod(level, 1000), level / 7 "
        "from dual connect by level <= 100000"
    )

    def run(self):
        global sink
        cursor = self.conn.cursor()
        cursor.arraysize = 1000
        cursor.prefetchrows = 1000
        cursor.execute(self.sql)
        rows = cursor.fetchall()
        assert len(rows) == self.units
        sink = rows[-1]
        cursor.close()


class InsertManyBenchmark(Benchmark):
    name = "executeMany insert 10k rows"
    units = 10000

    def setup(self):
        super().setup()
        self.rows = [
            (i, f"name {i}", i * 1.25, datetime.datetime(2020, 1, 1 + i % 28))
            for i in range(10000)
        ]
        cursor = self.conn.cursor()
        cursor.execute(
            """
            begin
              execute immediate 'drop table bench_t purge';
            exception
              when others then if sqlcode != -942 then raise; end if;
            end;"""
        )
        cursor.execute(
            "create table bench_t (id number, name varchar2(50), "
            "amount number(12, 2), created date)"
        )

    def run(self):
        cursor = self.conn.cursor()
        cursor.executemany(
            "insert into bench_t values (:1, :2, :3, :4)", self.rows
        )
        self.conn.commit()

    def teardown(self):
        self.conn.cursor().execute("drop table bench_t purge")
        super().teardown()


def main():
    print(f"python-oracledb {oracledb.__version__} (thin mode)")
    for cls in (
        ConnectBenchmark,
        PingBenchmark,
        QueryWithBindBenchmark,
        FetchBenchmark,
        InsertManyBenchmark,
    ):
        scores = [cls().measure() for _ in range(3)]
        micros = statistics.median(scores)
        print(
            f"{cls.name:<32}{micros / 1000:10.3f} ms/run"
            f"{cls.units * 1e6 / micros:12.0f} units/s"
        )


if __name__ == "__main__":
    main()
