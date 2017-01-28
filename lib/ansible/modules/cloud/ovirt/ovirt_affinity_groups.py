#!/usr/bin/python
# -*- coding: utf-8 -*-
#
# Copyright (c) 2016 Red Hat, Inc.
#
# This file is part of Ansible
#
# Ansible is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Ansible is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Ansible.  If not, see <http://www.gnu.org/licenses/>.
#

import traceback

try:
    import ovirtsdk4.types as otypes
except ImportError:
    pass

from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils.ovirt import (
    BaseModule,
    check_sdk,
    check_support,
    create_connection,
    equal,
    ovirt_full_argument_spec,
    search_by_name,
)


ANSIBLE_METADATA = {'status': ['preview'],
                    'supported_by': 'community',
                    'version': '1.0'}

DOCUMENTATION = '''
---
module: ovirt_affinity_groups
short_description: Module to manage affinity groups in oVirt
version_added: "2.3"
author: "Ondra Machacek (@machacekondra)"
description:
    - "This module manage affinity groups in oVirt. It can also manage assignments
       of those groups to VMs."
options:
    name:
        description:
            - "Name of the the affinity group to manage."
        required: true
    state:
        description:
            - "Should the affinity group be present or absent."
        choices: ['present', 'absent']
        default: present
    cluster:
        description:
            - "Name of the cluster of the affinity group."
    description:
        description:
            - "Description of the affinity group."
    host_enforcing:
        description:
            - "If I(true) VM cannot start on host if it does not satisfy the C(host_rule)."
            - "C(This parameter is support since oVirt 4.1 version.)"
    host_rule:
        description:
            - "If I(positive) I(all) VMs in this group should run on the this host."
            - "If I(negative) I(no) VMs in this group should run on the this host."
            - "C(This parameter is support since oVirt 4.1 version.)"
        choices:
          - positive
          - negative
    vm_enforcing:
        description:
            - "If I(true) VM cannot start if it does not satisfy the C(vm_rule)."
    vm_rule:
        description:
            - "If I(positive) I(all) VMs in this group should run on the host defined by C(host_rule)."
            - "If I(negative) I(no) VMs in this group should run on the host defined by C(host_rule)."
            - "If I(disabled) this affinity group doesn't take effect."
        choices:
          - positive
          - negative
          - disabled
    vms:
        description:
            - "List of the VMs names, which should have assigned this affinity group."
    hosts:
        description:
            - "List of the hosts names, which should have assigned this affinity group."
            - "C(This parameter is support since oVirt 4.1 version.)"
extends_documentation_fragment: ovirt
'''

EXAMPLES = '''
# Examples don't contain auth parameter for simplicity,
# look at ovirt_auth module to see how to reuse authentication:

# Create(if not exists) and assign affinity group to VMs vm1 and vm2 and host host1
- ovirt_affinity_groups:
    name: mygroup
    cluster: mycluster
    vm_enforcing: true
    vm_rule: positive
    host_enforcing: true
    host_rule: positive
    vms:
      - vm1
      - vm2
    hosts:
      - host1

# Detach VMs from affinity group and disable VM rule:
- ovirt_affinity_groups:
    name: mygroup
    cluster: mycluster
    vm_enforcing: false
    vm_rule: disabled
    host_enforcing: true
    host_rule: positive
    vms: []
    hosts:
      - host1
      - host2

# Remove affinity group
- ovirt_affinity_groups:
    state: absent
    cluster: mycluster
    name: mygroup
'''

RETURN = '''
id:
    description: ID of the affinity group which is managed
    returned: On success if affinity group is found.
    type: str
    sample: 7de90f31-222c-436c-a1ca-7e655bd5b60c
affinity_group:
    description: "Dictionary of all the affinity group attributes. Affinity group attributes can be found on your oVirt instance
                  at following url: https://ovirt.example.com/ovirt-engine/api/model#types/affinity_group."
    returned: On success if affinity group is found.
'''


class AffinityGroupsModule(BaseModule):

    def __init__(self, vm_ids, host_ids, *args, **kwargs):
        super(AffinityGroupsModule, self).__init__(*args, **kwargs)
        self._vm_ids = vm_ids
        self._host_ids = host_ids

    def build_entity(self):
        return otypes.AffinityGroup(
            name=self._module.params['name'],
            description=self._module.params['description'],
            positive=(
                self._module.params['vm_rule'] == 'positive'
            ) if self._module.params['vm_rule'] is not None else None,
            enforcing=(
                self._module.params['vm_enforcing']
            ) if self._module.params['vm_enforcing'] is not None else None,
            vms=[
                otypes.Vm(id=vm_id) for vm_id in self._vm_ids
            ] if self._vm_ids is not None else None,
            hosts=[
                otypes.Host(id=host_id) for host_id in self._host_ids
            ] if self._host_ids is not None else None,
            vms_rule=otypes.AffinityRule(
                positive=(
                    self._module.params['vm_rule'] == 'positive'
                ) if self._module.params['vm_rule'] is not None else None,
                enforcing=self._module.params['vm_enforcing'],
                enabled=(
                    self._module.params['vm_rule'] in ['negative', 'positive']
                ) if self._module.params['vm_rule'] is not None else None,
            ) if (
                self._module.params['vm_enforcing'] is not None or
                self._module.params['vm_rule'] is not None
            ) else None,
            hosts_rule=otypes.AffinityRule(
                positive=(
                    self._module.params['host_rule'] == 'positive'
                ) if self._module.params['host_rule'] is not None else None,
                enforcing=self._module.params['host_enforcing'],
            ) if (
                self._module.params['host_enforcing'] is not None or
                self._module.params['host_rule'] is not None
            ) else None,
        )

    def update_check(self, entity):
        assigned_vms = sorted([vm.id for vm in entity.vms])
        assigned_hosts = sorted([host.id for host in entity.hosts])

        return (
            equal(self._module.params.get('description'), entity.description) and
            equal(self._module.params.get('vm_enforcing'), entity.vms_rule.enforcing) and
            equal(self._module.params.get('host_enforcing'), entity.hosts_rule.enforcing) and
            equal(self._module.params.get('vm_rule') == 'positive', entity.vms_rule.positive) and
            equal(self._module.params.get('vm_rule') in ['negative', 'positive'], entity.vms_rule.enabled) and
            equal(self._module.params.get('host_rule') == 'positive', entity.hosts_rule.positive) and
            equal(self._vm_ids, assigned_vms) and
            equal(self._host_ids, assigned_hosts)
        )


def _get_obj_id(obj_service, obj_name):
    obj = search_by_name(obj_service, obj_name)
    if obj is None:
        raise Exception("Object '%s' was not found." % obj_name)
    return obj.id


def main():
    argument_spec = ovirt_full_argument_spec(
        state=dict(
            choices=['present', 'absent'],
            default='present',
        ),
        cluster=dict(default=None, required=True),
        name=dict(default=None, required=True),
        description=dict(default=None),
        vm_enforcing=dict(default=None, type='bool'),
        vm_rule=dict(default=None, choices=['positive', 'negative', 'disabled']),
        host_enforcing=dict(default=None, type='bool'),
        host_rule=dict(default=None, choices=['positive', 'negative']),
        vms=dict(default=None, type='list'),
        hosts=dict(default=None, type='list'),
    )
    module = AnsibleModule(
        argument_spec=argument_spec,
        supports_check_mode=True,
    )
    check_sdk(module)
    connection = create_connection(module.params.pop('auth'))

    # Check if unsupported parameters were passed:
    supported_41 = ('host_enforcing', 'host_rule', 'hosts')
    if not check_support(
        version='4.1',
        connection=connection,
        module=module,
        params=supported_41,
    ):
        module.fail_json(
            msg='Following parameters are supported since 4.1: {params}'.format(
                params=supported_41,
            )
        )

    try:
        clusters_service = connection.system_service().clusters_service()
        vms_service = connection.system_service().vms_service()
        hosts_service = connection.system_service().hosts_service()
        cluster_name = module.params['cluster']
        cluster = search_by_name(clusters_service, cluster_name)
        if cluster is None:
            raise Exception("Cluster '%s' was not found." % cluster_name)
        cluster_service = clusters_service.cluster_service(cluster.id)
        affinity_groups_service = cluster_service.affinity_groups_service()

        # Fetch VM ids which should be assigned to affinity group:
        vm_ids = sorted([
            _get_obj_id(vms_service, vm_name)
            for vm_name in module.params['vms']
        ]) if module.params['vms'] is not None else None
        # Fetch host ids which should be assigned to affinity group:
        host_ids = sorted([
            _get_obj_id(hosts_service, host_name)
            for host_name in module.params['hosts']
        ]) if module.params['hosts'] is not None else None

        affinity_groups_module = AffinityGroupsModule(
            connection=connection,
            module=module,
            service=affinity_groups_service,
            vm_ids=vm_ids,
            host_ids=host_ids,
        )

        state = module.params['state']
        if state == 'present':
            ret = affinity_groups_module.create()
        elif state == 'absent':
            ret = affinity_groups_module.remove()

        module.exit_json(**ret)
    except Exception as e:
        module.fail_json(msg=str(e), exception=traceback.format_exc())
    finally:
        connection.close(logout=False)


if __name__ == "__main__":
    main()
