# orhtancadmin
Console GUI based on whiptail to do basic administration on Orthanc DICOM server
Usage: orthancadmin.sh orhtanchost:8042
Works through Orthanc Rest API. Authentication is not supported yet.
Requires packages: jq, curl
Tested on Debian 11.

Currently implemented functions:
1) delete studies based on date period
2) switch to one of peers of orthanc servers
3) replication of studeies between orthanc servers - you can choose frew servers from orthanc peers,
   choose one of them as source and define time period to syncronize. Then it makes an inventory 
   of source orthanc and syncronously sends studies that are missing on target peers. It does check
   based on StudyInstanceUID and not aware of Instances.

For replication mode it is highly recommended to keep orthanc peers section in orthanc.json
exact the same on all peers.

To be done soon:
1) Modify patients both in sigle node mode and replication mode
2) Modify studies both in sigle node mode and replication mode
