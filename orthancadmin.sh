#!/bin/bash

orthanchost=$1
cleanupdatabase()
{
whiptail --title "Warning" --msgbox "This will really delete studies without undo option!!!" 0 0
clear
startdate=$(whiptail --title "Enter start date" --inputbox "" 0 0 "20210101" 3>&1 1>&2 2>&3)
enddate=$(whiptail --title "Enter end date" --inputbox "" 0 0 "20210101" 3>&1 1>&2 2>&3)

foundstudiesjson=`curl --silent --location --request POST "http://$orthanchost/tools/find" \
--header 'Content-Type: text/plain' \
--data-raw '{
"CaseSensitive": true,
"Expand": false,
"Full": true,
"Level": "Study",
"Limit": 0,
"Query": {
              "StudyDate" : "'$startdate'-'$enddate'"
},
"Short": true,
"Since": 0
}'`
studiesarray=(`jq -r '.[]' <<< "$foundstudiesjson"`)
for (( x=0; x<${#studiesarray[@]}; x++ ));
do
deleteresult=`curl --silent --location --request DELETE "http://$orthanchost/studies/${studiesarray[x]}"`
echo "submitted...........$x of ${#studiesarray[@]} delete jobs"
done
whiptail --title "Job completed" --msgbox "Submitted ${#studiesarray[@]} delete jobs" 0 0
tools
}

switchpeer()
{
peersjson=`curl --silent --location --request GET "http://$orthanchost/peers"`
peersarray=(`jq -r '.[]' <<<"$peersjson"`)
peernumber=()
peerurl=()
for (( x=0; x<${#peersarray[@]}; x++ ));
do
peerconfigjson=`curl --silent --location --request GET "http://$orthanchost/peers/${peersarray[x]}/configuration"`
peerurl+=(`jq -r '.Url' <<<"$peerconfigjson"|cut -d '/' -f3`)
peernumber+=(" ${peerurl[x]} ${peersarray[x]}")
done
menuitems=" ${peernumber[@]} "
choice=$(whiptail --clear --nocancel --notags --title "Choose Peer" --menu "" 0 0 0 $menuitems 3>&1 1>&2 2>&3)
orthanchost=`echo $choice|tr -d '"'`
mainmenu
}

replicationmode()
{
peersjson=`curl --silent --location --request GET "http://$orthanchost/peers"`
peersarray=(`jq -r '.[]' <<<"$peersjson"`)
peernumber=()
peerurl=()
for (( x=0; x<${#peersarray[@]}; x++ ));
do
peerconfigjson=`curl --silent --location --request GET "http://$orthanchost/peers/${peersarray[x]}/configuration"`
peerurl+=(`jq -r '.Url' <<<"$peerconfigjson"|cut -d '/' -f3`)
peernumber+=("${peerurl[x]} ${peersarray[x]} off ")
done
menuitems=" ${peernumber[@]} "
replicationarraystring=$(whiptail --clear --nocancel --title "Cluster Menu"  --checklist "Choose Cluster Peers" 0 0 0 $menuitems 3>&1 1>&2 2>&3)
replicationarray=(`echo $replicationarraystring|tr -d '"'`)
replicationnmenu
}

cleanwrongpatientid()
{
clear
peersjson=`curl --silent --location --request GET "http://$orthanchost/peers"`
peersarray=(`jq -r '.[]' <<<"$peersjson"`)
peernumber=()
peerurl=()
for (( x=0; x<${#peersarray[@]}; x++ ));
do
peerconfigjson=`curl --silent --location --request GET "http://$orthanchost/peers/${peersarray[x]}/configuration"`
peerurl+=(`jq -r '.Url' <<<"$peerconfigjson"|cut -d '/' -f3`)
peernumber+=(" $x ${peersarray[x]}")
done
menuitems=" ${peernumber[@]} "
choice=$(whiptail --clear --nocancel --notags --title "Choose Peer For Garbage Collection" --menu "" 0 0 0 $menuitems 3>&1 1>&2 2>&3)
garbagehost=${peersarray[choice]}
patientidfilter=$(whiptail --title "Enter Patient ID Regex Filter" --inputbox "" 0 0 "^[0-9]{8}$" 3>&1 1>&2 2>&3)
patientsarrayjson=`curl --silent --location --request GET "http://$orthanchost/patients"`
patientsarray=(`jq -r '.[]' <<<"$patientsarrayjson"`)
garbagepatientsarray=()
clear
for (( x=0; x<${#patientsarray[@]}; x++ ));
do
patientdetails=`curl --silent --location --request GET "http://$orthanchost/patients/${patientsarray[x]}"`
patientid=`jq -r '.MainDicomTags.PatientID' <<<"$patientdetails"`
patientidisgood=`echo $patientid|grep -c -E $patientidfilter`
if [[ $patientidisgood == 0 ]]
then
echo "${patientsarray[x]} is garbage.....:$patientid"
garbagepatientsarray+=(${patientsarray[x]})
else
echo "${patientsarray[x]} is good........:$patientid"
fi
done
if (whiptail --title  "Cleanup Garbage Patients" --yesno " Source peer: $systemname\n Target garbage peer: $garbagehost\n Garbage patients to move: ${#garbagepatientsarray[@]} of ${#patientsarray[@]}\n Start cleanup?" 0 0)  then
rm -f /tmp/failedgarbagelist.txt
touch /tmp/failedgarbagelist.txt
for (( x=0; x<${#garbagepatientsarray[@]}; x++ ));
do
sendresult=`curl --silent --location --request POST "http://$orthanchost/peers/$garbagehost/store" \
--header 'Content-Type: text/plain' \
--data-raw '{
"Asynchronous": false,
"Compress": true,
"Permissive": true,
"Priority": 0,
"Resources": [
"'${garbagepatientsarray[x]}'"
],
"Synchronous": true
}'`
failedinstances=`jq -r '.FailedInstancesCount' <<<"$sendresult"`
totalinstances=`jq -r '.InstancesCount' <<<"$sendresult"`
size=`jq -r '.SizeMB' <<<"$sendresult"`
if [[ $failedinstances == 0 ]]
then
echo "Sent patient ${garbagepatientsarray[x]} to $garbagehost success;  Sent instances: $totalinstances; Size: $size MB"
deleteresult=`curl --silent --location --request DELETE "http://$orthanchost/patients/${garbagepatientsarray[x]}"`
else
echo "Sent patient ${garbagepatientsarray[x]} to $garbagehost failed; Failed instances: $totalinstances"
echo ${garbagepatientsarray[x]} >> /tmp/failedgarbagelist.txt
echo
fi
done
failedpatients=`more /tmp/failedgarbagelist.txt|wc -l`
if [[ $failedpatients == 0 ]]
then
whiptail --title "Garbage patients cleanup completed without errors" --msgbox " Cleaned \n ${#garbagepatientsarray[@]} \n patients" 0 0
else
whiptail --title "Garbage patients cleanup completed with errors" --msgbox " Failed to clean \n $failedpatients of ${#garbagepatientsarray[@]} \n patients. \n See a list of failed patients in /tmp/failedgarbagelist.txt" 0 0
fi
mainmenu
else
mainmenu
fi
}

maintaingarbage()
{
toolsoptions="1 Manage_Garbage_Patients 2 Manage_Garbage_Studies 3 Return_To_Main_Menu"
choice=$(whiptail --clear --nocancel --title "Garbage Management" --menu "" 0 0 0 $toolsoptions 3>&1 1>&2 2>&3)
if [[ $choice == 1 ]]
then
cleanwrongpatientid
elif [[ $choice == 2 ]]
then
mainmenu
else
mainmenu
fi
}

tools()
{
toolsoptions="1 Switch_To_Peer 2 Replication_Mode 3 Manage_Garbage 4 Cleanup_Database 5 Return_To_Main_Menu"
choice=$(whiptail --clear --nocancel --title "Tools" --menu "" 0 0 0 $toolsoptions 3>&1 1>&2 2>&3)
if [[ $choice == 1 ]]
then
switchpeer
elif [[ $choice == 2 ]]
then
replicationmode
elif [[ $choice == 3 ]]
then
maintaingarbage
elif [[ $choice == 4 ]]
then
cleanupdatabase
else
mainmenu
fi
}

getsysteminfo()
{
systeminfojson=`curl --silent --location --request GET "http://$orthanchost/system"`
systemname=`jq -r '.Name' <<<"$systeminfojson"`
systemversion=`jq -r '.Version' <<<"$systeminfojson"`
}

patientadmin()
{
patientname=$(whiptail --title "Enter patient name" --inputbox "" 0 0 "" 3>&1 1>&2 2>&3)
foundpatientsjson=`curl --silent --location --request POST "http://$orthanchost/tools/find" \
--header 'Content-Type: text/plain' \
--data-raw '{
"CaseSensitive": false,
"Expand": true,
"Full": false,
"Level": "Patient",
"Limit": 20,
"Query": {
              "PatientName" : "'$patientname'*"
},
"Short": true,
"Since": 0
}'`


}

replicationsysteminfo()
{
systemnamearray=()
systemversionarray=()
for (( x=0; x<${#replicationarray[@]}; x++ ));
do
systeminfojson=`curl --silent --location --request GET "http://${replicationarray[x]}/system"`
systemnamearray+=(`jq -r '.Name' <<<"$systeminfojson"`)
systemversionarray+=(`jq -r '.Version' <<<"$systeminfojson"`)
done
replicationserversstring=`echo ${systemnamearray[@]}|tr -d '"'`
}

replicatestudies()
{
peernumber=()
peerurl=()
for (( x=0; x<${#replicationarray[@]}; x++ ));
do
peernumber+=("${replicationarray[x]} ${systemnamearray[x]} off ")
done
menuitems=" ${peernumber[@]} "
masterpeer=$(whiptail --clear --nocancel --notags --title "Choose Source Peer"  --radiolist "Studies will be replicated from source peer" 0 0 0 $menuitems 3>&1 1>&2 2>&3)
targetpeers=()
targetpeernames=()
echo "Source peer....$masterpeer"
for (( x=0; x<${#replicationarray[@]}; x++ ));
do


if [[ "$masterpeer" != "${replicationarray[x]}" ]]
then
targetpeers+=(${replicationarray[x]})
targetpeernames+=(${systemnamearray[x]})
fi
done
targetpeersstring=`echo ${targetpeers[@]}|tr -d '"'`
clear
startdate=$(whiptail --title "Enter start date" --inputbox "Source peer: $masterpeer; target peers $targetpeersstring" 0 0 "20210101" 3>&1 1>&2 2>&3)
enddate=$(whiptail --title "Enter end date" --inputbox "Source peer: $masterpeer; target peers $targetpeersstring" 0 0 "20210101" 3>&1 1>&2 2>&3)
if (whiptail --title  "Start replication" --yesno " Source peer: $masterpeer;\n Target peers $targetpeersstring;\n Study date range from $startdate to $enddate;\n Start replication?" 10 60)  then
#inventory master peer
masterpeerstudiesjson=`curl --silent --location --request POST "http://$masterpeer/tools/find" \
--header 'Content-Type: text/plain' \
--data-raw '{
"CaseSensitive": true,
"Expand": true,
"Full": true,
"Level": "Study",
"Limit": 0,
"Query": {
              "StudyDate" : "'$startdate'-'$enddate'"
},
"Short": true,
"Since": 0
}'`
masterpeerstudiesfound=(`jq -r '.[] .ID' <<<"$masterpeerstudiesjson"`)
masterpeerstudyinstances=(`jq -r '.[] .MainDicomTags.StudyInstanceUID' <<<"$masterpeerstudiesjson"`)
sentstudycount=0
for (( x=0; x<${#targetpeers[@]}; x++ ));
do
targetpeer=${targetpeers[x]}
targetpeername=${targetpeernames[x]}
for (( y=0; y<${#masterpeerstudyinstances[@]}; y++ ));
do
searchstudyattargetjson=`curl --silent --location --request POST "http://$targetpeer/tools/find" \
--header 'Content-Type: text/plain' \
--data-raw '{
"CaseSensitive": true,
"Expand": false,
"Full": true,
"Level": "Study",
"Limit": 0,
"Query": {
              "StudyInstanceUID" : "'${masterpeerstudyinstances[y]}'"
},
"Short": true,
"Since": 0
}'`
studyidattarget=`jq -r '.[]' <<<"$searchstudyattargetjson"`
if [[ "$studyidattarget" = "" ]]; then
submitjob=`curl --silent --location --request POST "http://$masterpeer/peers/$targetpeername/store" \
--header 'Content-Type: text/plain' \
--data-raw '{
"Asynchronous": true,
"Compress": true,
"Permissive": true,
"Priority": 0,
"Resources": [
"'${masterpeerstudiesfound[y]}'"
],
"Synchronous": false
}'`
jobid=`jq -r '.ID' <<<"$submitjob"`
echo "Sending to $targetpeername.....Job ID....$jobid............${masterpeerstudyinstances[y]}"
else
echo "Already at $targetpeername.....Study ID..$studyidattarget....${masterpeerstudyinstances[y]}"
fi
done
done
whiptail --title "Job completed" --msgbox "Replication jobs have been submitted" 0 0
replicationtools	 
else
replicationtools
fi
}

replicationtools()
{
menuoptions="1 Replicate_Studies 2 Resync_Studies 3 Replication_Tools 4 Main_Menu"
choice=$(whiptail --clear --nocancel --title "Replication Tools" --menu "Servers: $replicationserversstring" 0 0 0 $menuoptions 3>&1 1>&2 2>&3)
if [[ $choice == 3 ]]
then
replicationtools 
elif [[ $choice == 1 ]]
then
replicatestudies
else
mainmenu
fi
}

replicationnmenu()
{
replicationsysteminfo
mainmenuoptions="1 Patient_Level_Administration 2 Study_Level_Administration 3 Replication_Tools 4 Main_Menu"
choice=$(whiptail --clear --nocancel --title "Replication Menu" --menu "Servers: $replicationserversstring" 0 0 0 $mainmenuoptions 3>&1 1>&2 2>&3)
if [[ $choice == 3 ]]
then
replicationtools 
elif [[ $choice == 2 ]]
then
paientadmin
else
mainmenu
fi
}

mainmenu()
{
getsysteminfo
mainmenuoptions="1 Patient_Level_Administration 2 Study_Level_Administration 3 Tools 4 Exit"
choice=$(whiptail --clear --nocancel --title "Main menu" --menu "Connected to server $systemname ver. $systemversion at $orthanchost" 0 0 0 $mainmenuoptions 3>&1 1>&2 2>&3)
if [[ $choice == 3 ]]
then
tools
elif [[ $choice == 1 ]]
then
paientadmin
elif [[ $choice == 4 ]]
then
exit 0
else
mainmenu
fi
}





mainmenu