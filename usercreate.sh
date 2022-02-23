#!/bin/bash
useradd wauser
echo -e "wauser\nwauser" | passwd wauser
useradd db2mdm
echo -e "db2mdm\ndb2mdm" | passwd db2mdm
useradd db2dwc
echo -e "db2dwc\ndb2dwc" | passwd db2dwc
