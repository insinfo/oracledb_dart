# -----------------------------------------------------------------------------
# subclass.py (Section 9.2)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Copyright (c) 2017, 2023, Oracle and/or its affiliates.
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

import oracledb
import db_config


class MyConnection(oracledb.Connection):
    def __init__(self):
        print("Connecting to database")
        return super(MyConnection, self).__init__(
            user=db_config.user, password=db_config.pw, dsn=db_config.dsn
        )

    def cursor(self):
        return MyCursor(self)


class MyCursor(oracledb.Cursor):
    def execute(self, statement, args):
        print("Executing:", statement)
        print("Arguments:")
        for argIndex, arg in enumerate(args):
            print("  Bind", argIndex + 1, "has value", repr(arg))
            return super(MyCursor, self).execute(statement, args)

    def fetchone(self):
        print("Fetchone()")
        return super(MyCursor, self).fetchone()


con = MyConnection()
cur = con.cursor()

cur.execute("select count(*) from emp where deptno = :bv", (10,))
(count,) = cur.fetchone()
print("Number of rows:", count)
