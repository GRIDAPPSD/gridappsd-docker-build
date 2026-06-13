#!/bin/bash

PATH=$PATH:~/.local/bin

####
# pull the lyrasis/blazegraph:2.1.4 container
# create a intermediate build container and add the gridappsd configuration file
# start the build container and import the xml files
# checkout the Powergrid-Models 
#  update the constants.py
#  load the measurements
# print instructions for committing the build container, tagging and pushing to dockerhub
####

# set the tag container
GRIDAPPSD_TAG=':develop'
#GRIDAPPSD_TAG=':seto_cleanup'

export PYTHONWARNINGS="ignore"

usage () {
  /bin/echo "Usage:  $0 [-d]"
  /bin/echo "        -d      debug"
  exit 2
}

debug_msg() {
  msg=$1
  if [ $debug == 1 ]; then
    now=`date`
    echo "DEBUG : $now : $msg"
  fi
}

http_status_container() {
  cnt=$1

  echo " "
  echo "Getting $cnt status"
  if [ "$cnt" == "blazegraph" ]; then
    url=$url_blazegraph
  elif [ "$cnt" == "viz" ]; then
    url=$url_viz
  fi
  debug_msg "$cnt $url"
  status="0"
  count=0
  maxcount=10
  while [ $status -ne "200" -a $count -lt $maxcount ]
  do
    status=$(curl -s --head -w %{http_code} "$url" -o /dev/null)
    debug_msg "curl status: $status"
    sleep 2
    count=`expr $count + 1`
  done
  
  debug_msg "tried $url $count times, max is $maxcount"
  if [ $count -ge $maxcount ]; then
    echo "Error contacting $url ($status)"
    echo "Exiting "
    echo " "
    exit 1
  fi
}

build_dir=bzbuild/build_$(date +"%Y%m%d%H%M%S")

if [ -d $build_dir ]; then
  echo "$build_dir exists"
  echo "Exiting..."
  exit 1
fi

echo "Build directory: $build_dir"
mkdir -p $build_dir
cp $0 $build_dir
cp Dockerfile.gridappsd_blazegraph $build_dir
mkdir ${build_dir}/conf
cp -rp ./conf/rwstore.properties ${build_dir}/conf
cd $build_dir

echo "Logging to : ${build_dir}/create.log"

# Close STDOUT file descriptor
exec 1<&-
# Close STDERR FD
exec 2<&-

# Open STDOUT as $LOG_FILE file for read and write.
exec 1<>create.log

# Redirect STDERR to STDOUT
exec 2>&1

date

url_viz="http://localhost:8080/"
url_blazegraph="http://localhost:8889/bigdata/namespace/kb/"
data_dir="Powergrid-Models/platform/cimxml"
debug=0
exists=0

# parse options
while getopts dpt: option ; do
  case $option in
    d) # enable debug output
      debug=1
      ;;
    *) # Print Usage
      usage
      ;;
  esac
done
shift `expr $OPTIND - 1`

echo " "
echo "Getting blazegraph status"
status=$(curl -s --head -w %{http_code} "$url_blazegraph" -o /dev/null)
debug_msg "blazegraph curl status: $status"


docker pull lyrasis/blazegraph:2.1.4

TIMESTAMP=`date +'%y%m%d%H'`

echo "TIMESTAMP $TIMESTAMP"

docker build --build-arg TIMESTAMP="${TIMESTAMP}_${GITHASH}" -t gridappsd/blazegraph:build -f Dockerfile.gridappsd_blazegraph .

echo " "
echo "Running the build container to load the data"

# start it with the proper conf file
did=`docker run --cpuset-cpus "0-3" -d -p 8889:8080 gridappsd/blazegraph:build`
status=$?

echo "$did $status"

if [ "$status" -gt 0 ]; then
  echo " "
  echo "Error starting container"
  echo "Exiting "
  exit 1
fi

cwd=`pwd`

if [ -d Powergrid-Models ]; then
  cd Powergrid-Models
  git pull -v
  cd $cwd
else
  git clone http://github.com/GRIDAPPSD/Powergrid-Models  -b seto_cleanup 
  git clone http://github.com/GRIDAPPSD/CIMHub  -b develop
fi


# Setup python environment
cd CIMHub
poetry lock
poetry build
poetry install
# Use the python environment
PYTHON=$(poetry env info --executable)
cd ../

echo $PYTHON
$PYTHON --version

GITHASH=`git -C Powergrid-Models log -1 --pretty=format:"%h"`

http_status_container 'blazegraph'

bz_load_status=0
echo " "
echo "Importing blazegraph data"

cd Powergrid-Models
if [ ! -f envars.sh ]; then
  cp envars_docker.sh envars.sh
fi
declare -r DB_URL="http://localhost:8889/bigdata/namespace/kb/sparql"
declare -r CIMHUB_PATH="../../CIMHub/target/libs/*:../../CIMHub/cimhub/target/cimhub-0.0.2-SNAPSHOT.jar"
declare -r CIMHUB_PROG="gov.pnnl.gridappsd.cimhub.CIMImporter"
declare -r CIMHUB_UTILS="../CIMHub/src_python/cimhub/"

cat << EOF > cimhubconfig.json
{
  "blazegraph_url": "http://localhost:8889/bigdata/namespace/kb/sparql",
  "cim_ns": "<http://iec.ch/TC57/CIM100#"
}
EOF

# Clear blazegraph
curl -D- -X POST $DB_URL --data-urlencode "update=drop all"

# Import models
curl -D- -H "Content-Type: application/xml" --upload-file ./models/feeders/CIM/XML/ACEP_PSIL/ACEP_PSIL.xml -X POST $DB_URL
# epri will be added later
#curl -D- -H "Content-Type: application/xml" --upload-file ./models/feeders/CIM/XML/EPRI_DPV_J1.xml -X POST $DB_URL
curl -D- -H "Content-Type: application/xml" --upload-file ./models/feeders/CIM/XML/IEEE123/IEEE123.xml -X POST $DB_URL
curl -D- -H "Content-Type: application/xml" --upload-file ./models/feeders/CIM/XML/IEEE123_PV/IEEE123_PV.xml -X POST $DB_URL
curl -D- -H "Content-Type: application/xml" --upload-file ./models/feeders/CIM/XML/IEEE13/IEEE13.xml -X POST $DB_URL
curl -D- -H "Content-Type: application/xml" --upload-file ./models/feeders/CIM/XML/IEEE13_Assets/IEEE13_Assets.xml -X POST $DB_URL
curl -D- -H "Content-Type: application/xml" --upload-file ./models/feeders/CIM/XML/IEEE13_OCHRE/IEEE13_OCHRE.xml -X POST $DB_URL
# ieee123 waiting on conversion
#curl -D- -H "Content-Type: application/xml" --upload-file ./models/feeders/CIM/XML/ieee123apps.xml -X POST $DB_URL
curl -D- -H "Content-Type: application/xml" --upload-file ./models/feeders/CIM/XML/R2_12_47_2/R2_12_47_2.xml -X POST $DB_URL
curl -D- -H "Content-Type: application/xml" --upload-file ./models/feeders/CIM/XML/Transactive/Transactive.xml -X POST $DB_URL
curl -D- -H "Content-Type: application/xml" --upload-file ./models/feeders/CIM/XML/IEEE9500bal/IEEE9500bal.xml -X POST $DB_URL

#java -cp $CIMHUB_PATH $CIMHUB_PROG -u=$DB_URL -o=idx test

# Add houses
$PYTHON $CIMHUB_UTILS/InsertHouses.py cimhubconfig.json EE71F6C9-56F0-4167-A14E-7F4C71F10EAA 3 0 ./platform/houses/ieee9500bal_house_uuids.json    1.0
$PYTHON $CIMHUB_UTILS/InsertHouses.py cimhubconfig.json 9CE150A8-8CC5-A0F9-B67E-BBD8C79D3095 2 0 ./platform/houses/r2_12_47_2_house_uuids.json  1.0
$PYTHON $CIMHUB_UTILS/InsertHouses.py cimhubconfig.json E407CBB6-8C8D-9BC9-589C-AB83FBF0826D 5 0 ./platform/houses/ieee123pv_house_uuids.json   1.0
$PYTHON $CIMHUB_UTILS/InsertHouses.py cimhubconfig.json 503D6E20-F499-4CC7-8051-971E23D0BF79 3 0 ./platform/houses/transactive_house_uuids.json 1.0

#./test_all_houses.sh

#status=$?
#echo "status: $status"

echo " "
rangeCount=`curl -s -G -H 'Accept: application/xml' "${url_blazegraph}sparql" --data-urlencode ESTCARD | sed 's/.*rangeCount=\"\([0-9]*\)\".*/\1/'`
echo "Finished loading blazegraph houses ($rangeCount)"

echo " "
echo "----"
echo "docker commit $did gridappsd/blazegraph:${TIMESTAMP}_${GITHASH} "
docker commit $did gridappsd/blazegraph:${TIMESTAMP}_${GITHASH}
echo "docker stop $did"
docker stop $did
echo " "
echo "Run these commands to commit the container and push the container to dockerhub"
echo "----"
echo "docker tag gridappsd/blazegraph:${TIMESTAMP}_${GITHASH} gridappsd/blazegraph${GRIDAPPSD_TAG}"
echo "docker push gridappsd/blazegraph:${TIMESTAMP}_${GITHASH}"
echo "docker push gridappsd/blazegraph${GRIDAPPSD_TAG}"

exit 0
