#!/usr/bin/env python3

import sys
import os
import hashlib
import subprocess
import xml.etree.ElementTree as ET

import yaml

DATA_DISK_FORMAT = 'qcow2'
DATA_DISK_PATH = '/mnt/data/'

def generate_mac_address(name):
  checksum = hashlib.sha256(name.encode('utf-8')).hexdigest()
  return '02:%s:%s:%s:%s:%s' % (checksum[0:2], checksum[2:4], checksum[4:6], checksum[6:8], checksum[8:10])

def create_logical_volume(name, size):
  print("Creating logical volume '%s' ..." % (name))
  return subprocess.run(['lvcreate', '-y', '-L', size, '-n', name, 'vg0'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

def delete_logical_volume(name):
  print("Deleting logical volume '%s' ..." % (name))
  return subprocess.run(['lvremove', '-y', '/dev/vg0/%s' % name], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

def create_data_disk(name, size):
  print("Creating data disk '%s' ..." % (name))
  path = os.path.join(DATA_DISK_PATH, name + ".qcow2")
  return subprocess.run(['qemu-img', 'create', '-f', DATA_DISK_FORMAT, path, size])

def format_data_disk(name):
  print("Formatting data disk '%s' ..." % (name))
  path = os.path.join(DATA_DISK_PATH, name + ".qcow2")
  return subprocess.run(['virt-format', '-a', path, '--filesystem', 'ext4', '--partition'])

def attach_data_disk(name):
  print("Adding data disk '%s' to VM ..." % (name))
  path = os.path.join(DATA_DISK_PATH, name + ".qcow2")
  return subprocess.run(['virsh', 'attach-disk', name, '--source', path, '--target', 'vdb', '--persistent', '--driver', 'qemu', '--subdriver', 'qcow2'])

def remove_from_dhcp(name, mac, ip):
  print("Removing '%s' from DHCP ..." % (name))

  xml = "<host name='%s' mac='%s' ip='%s'/>" % (name, mac, ip)

  return subprocess.run(['virsh',
    'net-update', 'default', 'delete', 'ip-dhcp-host',
    xml,
    '--live', '--config'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

def destroy_virtual_machine(name):
  print("Shutting down '%s' ..." % (name))

  return subprocess.run(['virsh',
    'destroy', name], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

def delete_virtual_machine(name):
  print("Undefining virtual machine '%s' ..." % (name))

  return subprocess.run(['virsh',
    'undefine', name], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

def create_virtual_machine(name, cores, memory, lv_name, mac):
  print("Creating virtual machine '%s' ..." % (name))

  return subprocess.run(['virt-install',
    '--name', name,
    '--vcpus', str(cores),
    '--memory', str(memory),
    '--disk', 'path=/dev/vg0/%s' % lv_name,
    '--cdrom=/var/lib/libvirt/images/debian-9.1-amd64-preseed.iso',
    '--os-type=linux',
    '--os-variant=debianwheezy',
    '--network', 'default,mac=%s' % (mac),
    '--graphics=spice,listen=0.0.0.0',
    '--debug',
    '--console', 'pty,target_type=serial',
  ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

def add_to_dhcp(name, mac, ip):
  print("Adding '%s' to DHCP ..." % (name))

  xml = "<host name='%s' mac='%s' ip='%s'/>" % (name, mac, ip)

  subprocess.run(['virsh',
    'net-update', 'default', 'delete', 'ip-dhcp-host',
    xml,
    '--live', '--config'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

  return subprocess.run(['virsh',
    'net-update', 'default', 'add', 'ip-dhcp-host',
    xml,
    '--live', '--config'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

def sanity_check(config):
  # Check if a logical volume with this name already exists
  if os.path.exists('/dev/vg0/%s' % config['lv_name']):
      print("Logical volume '%s' already exists!" % (config['lv_name']))
      return False

  # Check if a machine with this name already exists
  result = verify_run(subprocess.run(['virsh', 'list', '--all', '--name'], stdout=subprocess.PIPE, stderr=subprocess.PIPE))

  if config['name'] in result.stdout.decode('utf-8').split('\n'):
    print("Machine with this name already exists!")
    return False

  # Check if this IP is already in use by a different machine
  result = verify_run(subprocess.run(['virsh', 'net-dumpxml', 'default'], stdout=subprocess.PIPE, stderr=subprocess.PIPE))
  xml = ET.fromstring(result.stdout)
  for host in xml.findall('./ip/dhcp/host'):
    if host.attrib['ip'] == config['ip']:
      if host.attrib['name'] != config['name'] or host.attrib['mac'] != config['mac']:
        print("IP address '%s' already in use by '%s' (MAC: %s)!" % (host.attrib['ip'], host.attrib['name'], host.attrib['mac']))
        return False

  return True


def verify_run(process):
  if process.returncode != 0:
    if process.stdout:
      print("STDOUT:")
      print(process.stdout.decode('utf-8'))

    if process.stderr:
      print("STDERR:")
      print(process.stderr.decode('utf-8'))

    sys.exit(-1)

  return process


def main(mode, path):
  config = {}

  with open(path, 'r') as stream:
    try:
      config = yaml.load(stream)
    except yaml.YAMLError as exc:
      print(exc)
      sys.exit(-1)

  vm_name = next(iter(config))

  config = config[vm_name]
  config['name'] = vm_name
  config['mac'] = generate_mac_address(vm_name)
  config['ip'] = '192.168.100.%d' % (config['ip'])
  config['lv_name'] = 'lv_%s' % (vm_name)

  if mode == 'create':
    print("Creating vm '%s' with the following configuration:" % (vm_name))
    print(config)

    if not sanity_check(config):
      sys.exit(-1)

    verify_run(create_logical_volume(config['lv_name'], config['disk']))


    verify_run(add_to_dhcp(vm_name, config['mac'], config['ip']))
    verify_run(create_virtual_machine(vm_name, config['cores'], config['memory'], config['lv_name'], config['mac']))

    if 'data_disk' in config:
      verify_run(create_data_disk(vm_name, config['data_disk']))
      verify_run(format_data_disk(vm_name))
      verify_run(attach_data_disk(vm_name))

  elif mode == 'delete':
    print("Deleting vm '%s' with the following configuration:" % (vm_name))
    print(config)

    # Do not verify this as it fails when the domain is already shut down
    destroy_virtual_machine(config['name'])
    remove_from_dhcp(vm_name, config['mac'], config['ip'])
    delete_virtual_machine(vm_name)
    delete_logical_volume(config['lv_name'])

  else:
    print("Unknown mode '%s'" % (mode))

if __name__ == "__main__":
  if len(sys.argv) != 3:
    print("Usage: vm_create.py create|delete <path/to/server.yaml>")
    sys.exit(-1)

  main(sys.argv[1], sys.argv[2])
