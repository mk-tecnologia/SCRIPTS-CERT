#!/usr/bin/env python3
"""Run the embedded LDAP discovery code against representative UCS records."""
import contextlib
import io
import sys
import types
from pathlib import Path

source = (Path(__file__).resolve().parents[1] / 'ucs-cert.sh').read_text()
code = source.split("<<'PYLDAP'\n", 1)[1].split('\nPYLDAP', 1)[0]
records = []


class LDAP:
    def search(self, **kwargs):
        assert kwargs['filter'] == '(univentionObjectType=computers/domaincontroller_backup)'
        return records


package = types.ModuleType('univention')
package.uldap = types.ModuleType('univention.uldap')
package.uldap.getMachineConnection = LDAP
sys.modules['univention'] = package
sys.modules['univention.uldap'] = package.uldap


def discover():
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        exec(compile(code, 'ucs-cert LDAP discovery', 'exec'), {})
    return output.getvalue()


assert discover() == ''
records.append(('cn=bkp,dc=example,dc=test', {
    'cn': [b'bkp'], 'associatedDomain': [b'example.test'],
    'aRecord': [b'192.168.170.19', b'192.168.170.18', b'192.168.170.18'],
}))
assert discover() == 'bkp.example.test\tbkp\t192.168.170.18,192.168.170.19\n'
for invalid in ({'cn': [b'bad']}, {'cn': [b'bad'], 'associatedDomain': [b'example.test'], 'aRecord': [b'garbage']}):
    records.append(('cn=bad,dc=example,dc=test', invalid))
    try:
        discover()
    except (SystemExit, ValueError):
        pass
    else:
        raise AssertionError('Invalid LDAP record accepted')
    records.pop()
print('UCS LDAP discovery tests passed')
