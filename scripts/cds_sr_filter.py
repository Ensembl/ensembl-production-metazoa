# See the NOTICE file distributed with this work for additional information
# regarding copyright ownership.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

import sys

seq4cds = dict()

for line_raw in sys.stdin:
  splitted = line_raw.split("\t")
  if len(splitted) < 9:
    sys.stdout.write(line_raw)
    continue

  seq_id, _src, _type, _start, _end, _hz, _strand, _phase, _quals = line_raw.split("\t")

  if _type != "CDS":
    sys.stdout.write(line_raw)
    continue

  id_qual = list(filter(lambda x: x.startswith("ID="), _quals.split(";")))
  if not id_qual:
    continue

  cds_id = id_qual[0][3:]
  if cds_id not in seq4cds:
    seq4cds[cds_id] = seq_id

  if seq_id != seq4cds[cds_id]:
    print(cds_id, seq_id, file=sys.stderr)
    continue

  sys.stdout.write(line_raw)

