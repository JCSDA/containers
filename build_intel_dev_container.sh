#!/bin/bash
# © Copyright 2020-2020 UCAR
# This software is licensed under the terms of the Apache Licence Version 2.0 which can be obtained at
# http://www.apache.org/licenses/LICENSE-2.0.


#------------------------------------------------------------------------
function get_ans {
    ans=''
    while [[ $ans != y ]] && [[ $ans != n ]]; do
      echo $1
      read ans < /dev/stdin
      if [[ -z $ans ]]; then ans=$defans; fi
      if [[ $ans != y ]] && [[ $ans != n ]]; then echo "You must enter y or n"; fi
    done
}

#------------------------------------------------------------------------
# This script creates and optionally distributes a new container
# It will create a docker container and optionally also a Charliecloud and
# a singularity container as well

if [[ $# -lt 1 ]]; then
   echo "usage: build_intel_app_container.sh <name> <tag> <hpc>"
   exit 1
fi

CNAME=${1:-"intel19-impi-dev"}
TAG=${2:-"latest"}
HPC=${3:-"0"}

if [[ $(echo ${CNAME} | cut -d- -f1) = "intel17" ]]; then
    export INTEL_TARBALL='./intel_tarballs/parallel_studio_xe_2017_update1.tgz'
    export INTEL_CONTEXT='./context17'
elif [[ $(echo ${CNAME} | cut -d- -f1) = "intel19" ]]; then
    export INTEL_TARBALL='./intel_tarballs/parallel_studio_xe_2020_cluster_edition.tgz'
    export INTEL_CONTEXT='./context19'
fi

# Stop if anything goes wrong
set -e

echo "Building Intel development container "

# create the Dockerfile
case ${HPC} in
    "0")
        hpccm --recipe ${CNAME}.py --format docker > Dockerfile.$CNAME
        ;;
    "1")
        hpccm --recipe ${CNAME}.py --userarg hpc="True" \
                                             pmi0="True" \
                                             --format docker > Dockerfile.$CNAME
        ;;
    "2")
        hpccm --recipe ${CNAME}.py --userarg hpc="True" \
                                             mellanox="True" \
                                             pmi0="True" \
                                             --format docker > Dockerfile.$CNAME
        ;;
    *)
        echo "ERROR: unsupported HPC option"
	      exit 1
        ;;
esac

echo "=============================================================="
echo "   Building Docker Image"
echo "=============================================================="

# build the Docker image
cd ${INTEL_CONTEXT}
ln -sf ../Dockerfile.${CNAME} .
#sudo docker image build --no-cache -f Dockerfile.${CNAME} -t jedi-${CNAME} .
sudo docker image build -f Dockerfile.${CNAME} -t jedi-${CNAME} .

# save the Docker image to a file:
cd ..
mkdir -p containers
sudo docker save jedi-${CNAME}:latest | gzip > containers/docker-${CNAME}.tar.gz

# Optionally copy to amazon S3
get_ans "Send Docker container to AWS S3?"
if [[ $ans == y ]] ; then
  echo "Sending to Amazon S3"
  aws s3 mv s3://privatecontainers/docker-jedi-${CNAME}.tar.gz s3://privatecontainers/docker-jedi-${CNAME}-revert.tar.gz
  aws s3 cp containers/docker-${CNAME}.tar.gz s3://privatecontainers/docker-jedi-${CNAME}.tar.gz
else
  echo "Not sending to Amazon S3"
fi

echo "=============================================================="
echo "   Building Singularity Image"
echo "=============================================================="
# Optionally build the Singularity image
get_ans "Build Singularity image?"
if [[ $ans == y ]] ; then
    echo "Building Singularity image"
    rm -f singularity_build.log
    sudo singularity build containers/jedi-${CNAME}.sif docker-daemon:jedi-${CNAME}:${TAG} 2>&1 | tee singularity_build.log

    get_ans "Push Singularity image to S3 and backup existing version?"
    if [[ $ans == y ]] ; then
       aws s3 mv s3://privatecontainers/jedi-${CNAME}.sif s3://privatecontainers/jedi-${CNAME}-revert.tar.gz
       aws s3 cp containers/jedi-${CNAME}.sif s3://privatecontainers/jedi-${CNAME}.sif
    fi
fi

echo "=============================================================="
echo "   Building Charliecloud Image"
echo "=============================================================="

# build the Charliecloud image
get_ans "Build Charliecloud image?"
if [[ $ans == y ]] ; then
    echo "Building Charliecloud image"
    sudo ch-builder2tar jedi-${CNAME} containers

    # Optionally copy to amazon S3
    get_ans "Push Charliecloud container to AWS S3?"
    if [[ $ans == y ]] ; then
      echo "Sending to Amazon S3"
      aws s3 cp s3://privatecontainers/ch-jedi-${CNAME}.tar.gz s3://privatecontainers/ch-jedi-${CNAME}-revert.tar.gz
      aws s3 cp containers/jedi-${CNAME}.tar.gz s3://privatecontainers/ch-jedi-${CNAME}.tar.gz
    else
      echo "Not sending to Amazon S3"
    fi

else
    echo "Not Building Charliecloud image"
fi
