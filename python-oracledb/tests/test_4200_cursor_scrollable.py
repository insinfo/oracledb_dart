# -----------------------------------------------------------------------------
# Copyright (c) 2020, 2025, Oracle and/or its affiliates.
#
# This software is dual-licensed to you under the Universal Permissive License
# (UPL) 1.0 as shown at https://oss.oracle.com/licenses/upl and Apache License
# 2.0 as shown at http://www.apache.org/licenses/LICENSE-2.0. You may choose
# either license.
#
# If you elect to accept the software under the Apache License, Version 2.0,
# the following applies:
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# -----------------------------------------------------------------------------

"""
4200 - Module for testing scrollable cursors
"""

import test_env


class TestCase(test_env.BaseTestCase):
    def test_4200(self):
        "4200 - test creating a scrollable cursor"
        cursor = self.conn.cursor()
        self.assertEqual(cursor.scrollable, False)
        cursor = self.conn.cursor(True)
        self.assertEqual(cursor.scrollable, True)
        cursor = self.conn.cursor(scrollable=True)
        self.assertEqual(cursor.scrollable, True)
        cursor.scrollable = False
        self.assertEqual(cursor.scrollable, False)

    def test_4201(self):
        "4201 - test scrolling absolute yields an exception (after result set)"
        cursor = self.conn.cursor(scrollable=True)
        cursor.arraysize = self.cursor.arraysize
        cursor.execute("select NumberCol from TestNumbers order by IntCol")
        with self.assertRaisesFullCode("DPY-2063"):
            cursor.scroll(12, "absolute")

    def test_4202(self):
        "4202 - test scrolling absolute (when in buffers)"
        cursor = self.conn.cursor(scrollable=True)
        cursor.prefetchrows = 0
        cursor.arraysize = self.cursor.arraysize
        cursor.execute("select NumberCol from TestNumbers order by IntCol")
        cursor.fetchmany()
        self.assertTrue(
            cursor.arraysize > 1,
            "array size must exceed 1 for this test to work correctly",
        )
        cursor.scroll(1, mode="absolute")
        (value,) = cursor.fetchone()
        self.assertEqual(value, 1.25)
        self.assertEqual(cursor.rowcount, 1)

    def test_4203(self):
        "4203 - test scrolling absolute (when not in buffers)"
        cursor = self.conn.cursor(scrollable=True)
        cursor.arraysize = self.cursor.arraysize
        cursor.execute("select NumberCol from TestNumbers order by IntCol")
        cursor.scroll(6, mode="absolute")
        (value,) = cursor.fetchone()
        self.assertEqual(value, 7.5)
        self.assertEqual(cursor.rowcount, 6)

    def test_4204(self):
        "4204 - test scrolling to first row in result set (in buffers)"
        cursor = self.conn.cursor(scrollable=True)
        cursor.arraysize = self.cursor.arraysize
        cursor.prefetchrows = 0
        cursor.execute("select NumberCol from TestNumbers order by IntCol")
        cursor.fetchmany()
        cursor.scroll(mode="first")
        (value,) = cursor.fetchone()
        self.assertEqual(value, 1.25)
        self.assertEqual(cursor.rowcount, 1)

    def test_4205(self):
        "4205 - test scrolling to first row in result set (not in buffers)"
        cursor = self.conn.cursor(scrollable=True)
        cursor.arraysize = self.cursor.arraysize
        cursor.prefetchrows = 0
        cursor.execute("select NumberCol from TestNumbers order by IntCol")
        cursor.fetchmany()
        cursor.fetchmany()
        cursor.scroll(mode="first")
        (value,) = cursor.fetchone()
        self.assertEqual(value, 1.25)
        self.assertEqual(cursor.rowcount, 1)

    def test_4206(self):
        "4206 - test scrolling to last row in result set"
        cursor = self.conn.cursor(scrollable=True)
        cursor.arraysize = self.cursor.arraysize
        cursor.execute("select NumberCol from TestNumbers order by IntCol")
        cursor.scroll(mode="last")
        (value,) = cursor.fetchone()
        self.assertEqual(value, 12.5)
        self.assertEqual(cursor.rowcount, 10)

    def test_4207(self):
        "4207 - test scrolling relative yields an exception (after result set)"
        cursor = self.conn.cursor(scrollable=True)
        cursor.arraysize = self.cursor.arraysize
        cursor.execute("select NumberCol from TestNumbers order by IntCol")
        with self.assertRaisesFullCode("DPY-2063"):
            cursor.scroll(15)

    def test_4208(self):
        "4208 - test scrolling relative yields exception (before result set)"
        cursor = self.conn.cursor(scrollable=True)
        cursor.arraysize = self.cursor.arraysize
        cursor.execute("select NumberCol from TestNumbers order by IntCol")
        with self.assertRaisesFullCode("DPY-2063"):
            cursor.scroll(-5)

    def test_4209(self):
        "4209 - test scrolling relative (when in buffers)"
        cursor = self.conn.cursor(scrollable=True)
        cursor.arraysize = self.cursor.arraysize
        cursor.prefetchrows = 0
        cursor.execute("select NumberCol from TestNumbers order by IntCol")
        cursor.fetchmany()
        message = "array size must exceed 1 for this test to work correctly"
        self.assertTrue(cursor.arraysize > 1, message)
        cursor.scroll(2 - cursor.rowcount)
        (value,) = cursor.fetchone()
        self.assertEqual(value, 2.5)
        self.assertEqual(cursor.rowcount, 2)

    def test_4210(self):
        "4210 - test scrolling relative (when not in buffers)"
        cursor = self.conn.cursor(scrollable=True)
        cursor.arraysize = self.cursor.arraysize
        cursor.execute("select NumberCol from TestNumbers order by IntCol")
        cursor.fetchmany()
        cursor.fetchmany()
        message = "array size must exceed 1 for this test to work correctly"
        self.assertTrue(cursor.arraysize > 1, message)
        cursor.scroll(3 - cursor.rowcount)
        (value,) = cursor.fetchone()
        self.assertEqual(value, 3.75)
        self.assertEqual(cursor.rowcount, 3)

    def test_4211(self):
        "4211 - test scrolling when there are no rows"
        self.cursor.execute("truncate table TestTempTable")
        cursor = self.conn.cursor(scrollable=True)
        cursor.execute("select * from TestTempTable")
        cursor.scroll(mode="last")
        self.assertEqual(cursor.fetchall(), [])
        cursor.scroll(mode="first")
        self.assertEqual(cursor.fetchall(), [])
        with self.assertRaisesFullCode("DPY-2063"):
            cursor.scroll(1, mode="absolute")

    def test_4212(self):
        "4212 - test scrolling with differing array and fetch array sizes"
        self.cursor.execute("truncate table TestTempTable")
        for i in range(30):
            self.cursor.execute(
                """
                insert into TestTempTable (IntCol, StringCol1)
                values (:1, null)
                """,
                [i + 1],
            )
        for arraysize in range(1, 6):
            cursor = self.conn.cursor(scrollable=True)
            cursor.arraysize = arraysize
            cursor.execute("select IntCol from TestTempTable order by IntCol")
            for num_rows in range(1, arraysize + 1):
                cursor.scroll(15, "absolute")
                rows = cursor.fetchmany(num_rows)
                self.assertEqual(rows[0][0], 15)
                self.assertEqual(cursor.rowcount, 15 + num_rows - 1)
                cursor.scroll(9)
                rows = cursor.fetchmany(num_rows)
                num_rows_fetched = len(rows)
                self.assertEqual(rows[0][0], 15 + num_rows + 8)
                self.assertEqual(
                    cursor.rowcount, 15 + num_rows + num_rows_fetched + 7
                )
                cursor.scroll(-12)
                rows = cursor.fetchmany(num_rows)
                count = 15 + num_rows + num_rows_fetched - 5
                self.assertEqual(rows[0][0], count)
                count = 15 + num_rows + num_rows_fetched + num_rows - 6
                self.assertEqual(cursor.rowcount, count)

    def test_4213(self):
        "4213 - test calling scroll() with invalid mode"
        cursor = self.conn.cursor(scrollable=True)
        cursor.arraysize = self.cursor.arraysize
        cursor.execute("select NumberCol from TestNumbers order by IntCol")
        cursor.fetchmany()
        with self.assertRaisesFullCode("DPY-2009"):
            cursor.scroll(mode="middle")

    def test_4214(self):
        "4214 - test scroll after fetching all rows"
        cursor = self.conn.cursor(scrollable=True)
        cursor.arraysize = 5
        cursor.prefetchrows = 0
        cursor.execute("select NumberCol from TestNumbers order by IntCol")
        cursor.fetchall()
        cursor.scroll(5, mode="absolute")
        (value,) = cursor.fetchone()
        self.assertEqual(value, 6.25)
        self.assertEqual(cursor.rowcount, 5)


if __name__ == "__main__":
    test_env.run_test_cases()
