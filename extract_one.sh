#!/bin/bash
DIR="$(dirname "$(readlink -f "$0")")"
FIRMAFL_ROOT="${DIR}/FirmAFL"

export USER=`whoami`
service postgresql start

echo -n "[*] Waiting for postgresql database to become available ...";
while true; do
    psql -U firmadyne -h 127.0.0.1 -d firmware -c 'select 1' > /dev/null 2>/dev/null && break
    echo -n "."
    sleep 1
done
echo " done!"

experiment_id=$1


# Mapping between experiment ids to firmadyne-sample ids
declare -A id_mapping=(
        ["9925"]="9925"     # DAP-2695 httpd
        ["9050"]="9050"     # DIR-815  hwedwig.cgi
        ["9054"]="9054"     # DIR-817LW hnap
        ["10566"]="10566"   # DIR-850L hnap
        ["10853"]="10853"   # DIR-825 httpd
        ["129780"]="12978"  # TV-IP110WN video.cgi
        ["129781"]="12978"  # TV-IP110WN network.cgi
        ["161160"]="16116"  # TEW-632BRP miniupdnpd
        ["161161"]="16116"  # TEW-632BRP httpd
        # Images with missing FirmAFL config
        # [""]="105568" # WR940N httpd
        # [""]="105569" # DSL-3782 tcapi (this one has 5 sub experiments)
        # [""]="105570" # WNAP320 lighttpd
        # [""]="13476"  # TEW-813DRU jjhttpd
)


# Mapping between experiment ids to FirmAFL samples
# This is required because the FirmAFL and firmadyne sample name differs
declare -A sample_mapping=(
        ["9925"]="DAP-2695_REVA_FIRMWARE_1.11.RC044.ZIP"
        ["9050"]="DIR-815_FIRMWARE_1.01.ZIP"
        ["9054"]="DIR-817LW_REVA_FIRMWARE_1.00B05.ZIP"
        ["10566"]="DIR-850L_FIRMWARE_1.03.ZIP"
        ["10853"]="DIR-825_REVB_FIRMWARE_2.02.ZIP"
        ["129780"]="fw_tv-ip110wn_v2(1.2.2.68).zip"
        ["129781"]="fw_tv-ip110wn_v2(1.2.2.68).zip"
        ["161160"]="tew-632brpa1_(fw1.10b32).zip"
        ["161161"]="tew-632brpa1_(fw1.10b32).zip"
        # Images with missing FirmAFL config
        ["13476"]="_FW_TEW-813DRU_v1(1.00B23).zip" 
        # The ids below depend on the extraction order, as they exist neither in the orignal firmadyne database, nor
        # the one shipped with FirmAFL (https://raw.githubusercontent.com/zyw-200/FirmAFL_2020/master/firmadyne_modify/data)
        ["105568"]="TL-WR940N(US)_V4_160617_1476690524248q.zip"
        ["105569"]="DSL-3782_A1_EU_1.01_07282016.zip"
        ["105570"]="WNAP320_V3.0.5.0.zip"

)

image_id=${id_mapping[$experiment_id]}
image_filename=${sample_mapping[$experiment_id]}


if [[ ${image_id} == "" ]]; then
    echo "Supplied ${experiment_id} does not have a backing image, exiting"
    exit -1
fi

echo "[+] Cleaning up previously unpacked images"
cd ${FIRMAFL_ROOT}
rm -r ./image_${experiment_id}
rm -r ./image_${image_id}
cd ${FIRMAFL_ROOT}/firmadyne
rm ./images/${image_id}.tar.gz


echo "[+] Extracting image"
# brand seems to be only used upon first extraction, but luckily, we use firmadyne's database
# hence, we can skip the -b flag for the extracter and just unpack all images
python3 ./sources/extractor/extractor.py -sql 127.0.0.1 -np -nk ${FIRMAFL_ROOT}/firmware/${image_filename} images

echo "[+] Creating FirmAFL image"
./scripts/getArch.sh ${FIRMAFL_ROOT}/firmadyne/images/${image_id}.tar.gz
./scripts/makeImage.sh ${image_id}
./scripts/inferNetwork.sh ${image_id}
cd ${FIRMAFL_ROOT}

# Firmware with id 9050 is the only firmware in the (publicly available) firmafl dataset with
# mipsel as architecture. All others samples are mipseb (aka, mips for Qemu)
if [[ ${image_id} == "9050" ]]
then
    arch="mipsel"
else
    arch="mips"
fi

if [[ ${FIRMAFL_MODE} == "full" ]]; then
    python2 Full_setup.py ${image_id} ${arch}
    # The original scripts assume qemu is stored as qemu-system-mips/el-full
    cp ./image_${image_id}/qemu-system-${arch} ./image_${image_id}/qemu-system-${arch}-full
    cp ${DIR}/start_full.sh ./image_${image_id}
else
    python2 FirmAFL_setup.py ${image_id} ${arch}
fi

# We will consolidate the files from the above generated images and the provided FirmAFL config files.
# Unfortunately, the configs hardcode relative paths, so we need to move and copy the image directories as well.
# Can this be more efficient and using less disk space? Surely - but we are trying to get an as faithful as possible setup.

# These are safety copies, in case something went wrong with the official firmafl setup scripts
# This happens for instance when experiment and image id are not equal.
cd ${FIRMAFL_ROOT}
echo "[+] Setting up experiment ${experiment_id} (image id: ${image_id})"

if [ ${experiment_id} != ${image_id} ]; then
    cp -r ${FIRMAFL_ROOT}/image_${image_id} ./image_${experiment_id}
fi
cp ${FIRMAFL_ROOT}/FirmAFL_config/${experiment_id}/* ./image_${experiment_id}/

# The experiment scripts expect keyword file names to include the ID, the firmafl-config directories are mising these tho
cp ${FIRMAFL_ROOT}/FirmAFL_config/${experiment_id}/keywords ./image_${experiment_id}/keywords_${experiment_id}
# Also, the firmafl setup script may not be able to automatically move all seeds to the input directories, so we take care of it
cp ${FIRMAFL_ROOT}/FirmAFL_config/${experiment_id}/seed* ./image_${experiment_id}/inputs/seed

# The firmafl script do not copy over the files correctly in case of image/experiment id mismatch. Hence, we do this manually here.
if [[ ${experiment_id} == "129780" ]]; then
    echo "[+] Setting up the missing files for ${experiment_id}"
    mkdir -p ./image_${experiment_id}/var/run/
    mkdir -p ./image_${experiment_id}/var/tmp
    # file pos file is wrong. correct paths below
    cp ${FIRMAFL_ROOT}/FirmAFL_config/missing_file/${experiment_id}/* ./image_${experiment_id}/var/config/
fi

if [[ ${experiment_id} == "129781" ]]; then
    echo "[+] Setting up the missing files for ${experiment_id}"
    cp ${FIRMAFL_ROOT}/FirmAFL_config/missing_file/${experiment_id}/net.conf ./image_${experiment_id}/var/config/
    mkdir -p ./image_${experiment_id}/var/tmp
fi

if [[ ${experiment_id} == "161161" ]]; then
    echo "[+] Setting up the missing files for ${experiment_id}"
    cp ${FIRMAFL_ROOT}/FirmAFL_config/missing_file/${experiment_id}/* ./image_${experiment_id}/etc
fi

# We experienced some samples required more startup time - so we just globally increase it.
echo "[+] Adjusting time budget for ${experiment_id}"
if [[ ${FIRMAFL_MODE} == "full" ]]; then
    sed -i 's/sleep 80/sleep 160/' ${FIRMAFL_ROOT}/image_${experiment_id}/start_full.sh
else
    sed -i 's/time.sleep(80)/time.sleep(160)/' ${FIRMAFL_ROOT}/image_${experiment_id}/start.py
fi
