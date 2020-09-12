# Sample postprocessor script that will do the following:
# - read the generate hosts file + parse it
# - avoid duplicate hosts
# - map the hosts sysobj id to the info from the SYSOBJID MAP FILE
# - write an output file in the output folder
#
# Hosts stored in the .ignore file will be removed from the output
# Only the devices that are in the "supported_vendors" list will be kept
#
# Input: requires that the hosts/hosts file was generated by the discovery
# Output: 
#    - output/network-discovery.csv: CSV file with all discovered hosts
#    - output/output.ansible: a hosts file that could be used by Ansible

import json
import os
import sys
import ipaddress
import yaml
import re


hostsfile = os.environ.get("E_HOSTSFILE")
sysobjidmap = os.environ.get("E_SNMP_SYSOBJID_MAPFILE")

ignore_hosts_file = os.environ.get("E_IGNORE_FILE", "static.ignore")
ignore_host_list = []

output_folder = os.environ.get("E_OUTPUT_FOLDER", "output")

supported_vendors = [ "Accton Technology", "ciena", "cisco", "juniper", "oneaccess", "wwpacket_ciena" ]

sycontact_credentials_map = {
    "default": "TACACS_USERS"
}


# Example how to categorize an IP address to a function in your network
# This requires that the correct env vars are known
ipranges = {
    "MGMT_RANGES": {
        "network": os.environ.get("MGMT_RANGES", "()"),
        "function": "CES",
    },
    "DCN": {
        "network": os.environ.get("E_DCN", "()"),
        "function": "DCN",
    },
    "CORE_LOOPBACK": {
        "network": os.environ.get("E_CORE_LOOPBACK", "()"),
        "function": "CORE",
    },
    "P2P": {
        "network": os.environ.get("E_P2P", "()"),
        "function": "CPE",
        "service": [ "CI" ]
    },
}

for x in ipranges:
    ipranges[x]["network"] = [
                    ipaddress.ip_network(x) for x in
                      ipranges[x]["network"].replace("(", "").replace(")", "").replace('"', "").split(" ")
                    if x
                  ]


# load the sysobjid mapping file, it's in yaml format
sysobjid_mapping = {}
with open(sysobjidmap, "r") as fd:
    sysobjid_mapping = yaml.safe_load(fd)

# populate the ignore_host_list based on the .ignore file
if os.path.isfile(ignore_hosts_file):
    with open(ignore_hosts_file, "r") as fd:
        ignore_host_list = fd.readlines()
    ignore_host_list = [ x.rstrip().split()[0] for x in ignore_host_list if x.rstrip() ]


class Host(object):
    """
    Store a single host.

    Device ID = hostname if it exists or else the IP address
    """

    CSV_HEADER = [ "host", "managementip", "ip", "domainname", "community", "sysobjid", "vendor", "hwtype", "function", "service", "datasource", "napalm_driver", "sysdescr", "syscontact", "protocol", "errors" ]

    def __init__(self, categorize=True, **kwargs):
        """
        Expect a dict of the parsed column names:
          MGMTIP:HOSTNAME:COMMUNITY:SYSOBJID:SYSDESCR:SYSCONTACT

        id = hostname or mgmtip
        """
        hostname = kwargs.get('HOSTNAME', None)
        domainname = None
        if hostname and "." in hostname:
            domainname = ".".join(hostname.split(".")[1:]).lower()
            hostname = hostname.split(".")[0]

        self.autocategorize = categorize

        # parameters passed via commandline, found in the discovery hosts file
        self.host = hostname.lower() if hostname else kwargs["MGMTIP"]
        self.domainname = domainname
        self.ip = [ kwargs["MGMTIP"] ]
        self.ip_removed = []    # store removed IP's, in some cases this is needed
        self.managementip = None  # ip holds all known IP's,
                                  # management ip should be the real mgmt ip
        self.community = kwargs.get('COMMUNITY', None)
        self.sysobjid = kwargs.get('SYSOBJID', None)
        self.sysdescr = kwargs.get('SYSDESCR', None)
        self.syscontact = kwargs.get('SYSCONTACT', None)
        self.protocol = kwargs.get('PROTO', None)

        # parameters found by the categorize function
        self.function = None    # ex: CPE|PE
        self.vendor = None      # ex: cisco, ciena, oneaccess
        self.hwtype = None      # ex: C891F, LBB_140
        self.service = []       # ex: L3VPN, L2VPN
        self.datasource = "network-discovery"   # data source
        self.napalm_driver = "" # napalm driver if we can find it
        self.errors = []        # if there are any errors with parsing etc
        self.credentials = "TACACS_USERS"  # used to group devices per credential group

        if self.sysobjid:
            self.sysobjid = self.sysobjid.replace(".1.3.6.1.4.1", "1.3.6.1.4.1")
            if self.sysobjid in sysobjid_mapping.get('sysobjid_map', {}):
                self.vendor = sysobjid_mapping["sysobjid_map"][self.sysobjid]["vendor"]
                self.hwtype = sysobjid_mapping["sysobjid_map"][self.sysobjid]["hwtype"]
                self.napalm_driver = sysobjid_mapping["sysobjid_map"][self.sysobjid]["napalm_os"]

        if self.autocategorize:
            self.categorize()

        self.set_credentials()


    def upsert(self, hostobj):
        """
        Used for merging two hosts, the extra parameters of the
        new hostobj are added to the existing host
        """
        #print("upsert object")
        self.ip = list(set(self.ip + hostobj.ip))

        for x in [ "community", "sysobjid", "sysdescr", "protocol" ]:
            self.__dict__[x] = self.__dict__[x] or hostobj.__dict__[x]

        if self.autocategorize:
            self.categorize()

        self.set_credentials()



    def set_credentials(self):
        """
        Set the credentials based on some rules.
        Ex value of the syscontact my define a different set of
           credentials
        """
        syscontact = self.syscontact.upper() if self.syscontact else "default"
        self.credentials = sycontact_credentials_map.get(syscontact, sycontact_credentials_map["default"])


    def categorize(self):
        pass


    def tojson(self, indent=4):
        return json.dumps({ x: self.__dict__[x] for x in self.__dict__ })

    def tocsv(self, delim=",", altdelim="_", listdelim=";", headeronly=False):

        if headeronly:
            return delim.join(self.CSV_HEADER)

        cols = []
        for x in self.CSV_HEADER:
            if type(self.__dict__[x]) is list:
                cols.append(listdelim.join(self.__dict__[x]))
            else:
                cols.append(self.__dict__[x] or "")
        cols = map(lambda x: x.replace(delim, altdelim), cols)
        return delim.join(cols)

    def __eq__(self, other):
        return self.host == other.host or set(self.ip) & set(other.ip)

    def __ne__(self, other):
        return self.host != other.host and not set(self.ip) & set(other.ip)

    def __repr__(self):
        return "<Host> {}".format(self.host)



class CustomHost(Host):


    def update_management_ip(self):
        """
        Try to find the best management IP out of the ip list
        """

        if not self.ip:
            return

        # if there is only 1 IP known then this will be the
        # mgmt IP
        if self.ip and len(self.ip) == 1:
            self.managementip = self.ip[0]
            return

        # if there is IPVPN + CI then prefer the LOWEST IPVPN Loopback IP
        if len(self.service) > 1 and "IPVPN" in self.service and "CI" in self.service:
            ipvpn_ip = []
            other_ip = []
            for ip in self.ip:
                ipaddr = ipaddress.ip_address(ip)
                for network in ipranges["IPVPN_LOOPBACK"]["network"]:
                    if ipaddr in network:
                        ipvpn_ip.append(ip)
                    else:
                        other_ip.append(ip)
            self.ip = sorted(ipvpn_ip) + sorted(other_ip)

        # take the first IP as management IP
        self.managementip = self.ip[0]


    def categorize(self):
        """
        Try to determine the type, service, etc
        """
        self.categorize_by_ip()
        self.fix_settings()
        self.verify_host_parameters()
        self.update_management_ip()


    def fix_settings(self):
        """
        In case of errors we may try to fix the issue,
        example:
        when a device is both PE + CPE and there is a CORE IP
        known then the device is definitely a PE router and
        all CPE IP's can be removed
        """

        # if CORE + CPE in function then change to CORE only
        # if there is at least a single CORE_LOOPBACK IP
        if len(self.function) > 1 and "CORE" in self.function:
            core_ips = []
            other_ips = []
            for ip in self.ip:
                ipaddr = ipaddress.ip_address(ip)
                for network in ipranges["CORE_LOOPBACK"]["network"]:
                    if ipaddr in network:
                        core_ips.append(ip)
                    else:
                        other_ips.append(ip)
            if core_ips:
                self.ip = core_ips
                self.ip_removed = other_ips
                self.function = ["CORE"]

        # if multiple functions and it includes DCN then
        # prefer interfaces in the DCN_LOOPBACK ranges
        if len(self.function) > 1 and "DCN" in self.function:
            dcn_loopback = []
            other_ip = []
            for ip in self.ip:
                ipaddr = ipaddress.ip_address(ip)
                for network in ipranges["DCN_LOOPBACK"]["network"]:
                    if ipaddr in network:
                        dcn_loopback.append(ip)
                    else:
                        other_ip.append(ip)
            if dcn_loopback:
                self.ip = dcn_loopback
                self.ip_removed = other_ip
                self.function = [ "DCN" ]



    def categorize_by_ip(self):
        """
        Try to categorize the host based on the IP address
        """
        functions = []
        services = []

        # get all functions and services based on the IP addresses
        for ip in self.ip:
            if not ip:
               continue
            ipaddr = ipaddress.ip_address(ip)
            for iprange in ipranges:
                for network in ipranges[iprange]["network"]:
                    if ipaddr in network:
                        functions.append(ipranges[iprange]["function"])
                        services += ipranges[iprange].get("service", [])

        self.function = list(set(functions))
        self.service = list(set(services))


    def verify_host_parameters(self):
        """
        Make sure there are no unexpected host types or services
        """
        if len(self.function) > 1:
            errormsg = "host {} cannot have multiple functions: {}".format(self.host, self.function)
            if errormsg not in self.errors:
                self.errors.append(errormsg)
                print("ERROR: host {} cannot have multiple functions: {}".format(self.host, self.function))


    def netbackup(self, use_ignored_hosts=True):
        """
        Returns true if the host is a good host to include in the netbackup report
        """

        # include unknown devices
        if not self.vendor:
            return True

        # skip hosts in the ignored hosts list
        if use_ignored_hosts and (self.host in ignore_host_list or self.managementip in ignore_host_list):
            return False

        return True if self.vendor in supported_vendors else False






class HostList(list):
    """
    Collection of Host objects
    """

    def __init__(self, *args):
        list.__init__(self, *args)


    def append(self, *args):
        """
        Appends or upserts a new host
        """
        new_elements  = []
        for a in args:
            if a and a not in self:
                new_elements.append(a)
            else:
                # TODO: upsert element
                found = list(filter(lambda x: a == x, self))
                if found:
                    found[0].upsert(a)

        if new_elements:
            super().append(*new_elements)


    def categorize(self):
        for x in self:
            x.categorize()


    def tojson(self, indent=4):
        for host in self:
            print(host.tojson(indent=indent))

    def tocsv(self, filename=None):
        showheader = True
        writer = open(filename, 'w') if filename else sys.stdout
        for host in self:
            if showheader:
                print(host.tocsv(headeronly=True), file=writer)
                showheader = False
            print(host.tocsv(), file=writer)


    def report_netbackup(self):
        showheader = True
        for host in self:
            if showheader:
                print(host.tocsv(headeronly=True))
                showheader = False
            if host.netbackup():
                print(host.tocsv())


    def report_dns_hosts(self, filename=None, include_unknown=False):
        """
        Create a DNS hosts files
        Format:
        mgmtip    hostname   hostname.domain
        """
        writer = open(filename, 'w') if filename else sys.stdout
        print("###### do not edit below this line - these entries are generated automatically ######", file=writer)
        print("", file=writer)
        for host in self:
            if not host.managementip and not include_unknown:
                continue
            if host.domainname:
                host_domain = "{}.{}".format(host.host, host.domainname)
            else:
                host_domain = ""
            print("{}\t{}\t{}".format(host.managementip, host.host, host_domain), file=writer)



    def report_ansible(self, filter=True, filename=None, include_unknown=False):
        """
        Create an ansible hosts file with format:
        hosts without napalm_driver are stored in the unknown group

        [credentials-group]
        managementip    HOSTNAME=host   FUNCTION=function   SERVICE=service    MULTISERVICE=true|false    snmp_community=community    os=napalm_driver

        [unknown]
        managementip    HOSTNAME=host   FUNCTION=function   SERVICE=service    MULTISERVICE=true|false    snmp_community=community    os=napalm_driver
        """
        report = {}
        writer = open(filename, 'w') if filename else sys.stdout

        for host in self:
            if filter and not host.netbackup():
                continue

            group = host.credentials
            os = host.napalm_driver
            entry = "{}    HOSTNAME={}".format(host.managementip, host.host)
            if os:
                entry += "    os={}".format(os)
            if host.function:
                entry += "    FUNCTION={}".format(",".join(host.function))
            if host.service:
                entry += "    SERVICE={}".format(",".join(host.service))
            if len(host.service) > 1:
                entry += "    MULTISERVICE=true"
            else:
                entry += "    MULTISERVICE=false"
            if host.community:
                entry += "    snmp_community={}".format(host.community)
            if host.protocol:
                entry += "    PROTOCOL={}".format(",".join(host.protocol))
            if not group or not os:
                group = "unknown"
            report.setdefault(group, [])
            report[group].append(entry)

        for group in report:
            if group == "unknown" and not include_unknown:
                continue
            print("\n" * 4, file=writer)
            print("[{}]".format(group), file=writer)
            print("\n".join(report[group]), file=writer)




def parse_discovery_file(f, delim=":"):
    """
    Read the discovery file line by line and return a
    dictionary for each line with { colname: value, }

    Format of input file:
        MGMTIP:HOSTNAME:COMMUNITY:SYSOBJID:SYSDESCR
    """

    colmap = {}
    with open(f, "r") as fd:
        for (cnt, line) in enumerate(fd.readlines()):
            line = line.strip()
            rec = {}
            if cnt == 0:
                colmap = { i: c for (i, c) in enumerate(line.split(delim)) }
                continue

            yield { colmap[i]: c for (i, c) in enumerate(line.split(delim)) }





def main():
    hostlist = HostList()

    for d in parse_discovery_file(hostsfile):
        h = CustomHost(**d)
        if h.host:
            hostlist.append(h)

    hostlist.tocsv(filename=os.path.join(output_folder, "network-discovery.csv"))
    hostlist.report_ansible(filename=os.path.join(output_folder, "hosts.ansible"))
    hostlist.report_dns_hosts(filename=os.path.join(output_folder, "hosts.dns"))


if __name__ == '__main__':
    main()


