#!/bin/bash

DIR="$(dirname "$(readlink -f "$0")")"
FIRMADYNE_DIR=$DIR/FirmAFL/firmadyne

cd $DIR

git clone https://github.com/fuzz-evaluator/FirmAFL-upstream.git FirmAFL
#git clone https://github.com/zyw-200/FirmAFL_2020.git FirmAFL
cd FirmAFL && git checkout $FIRMAFL_COMMIT && cd ..

if [[ ${FIRMAFL_MODE} = "full" ]]; then
    echo "[!] Building firmafl in full mode, skipping user mode"
else
    echo "[*] Building user mode firmafl"
    cd $DIR/FirmAFL/user_mode
    ./configure \
        --target-list=mipsel-linux-user,mips-linux-user,arm-linux-user \
        --static \
        --disable-werror && \
        make
fi

if [[ ${FIRMAFL_MODE} = "full" ]]; then
    echo "[!] Applying patch to build FirmAFL full"
    sed -i 's|//#define FULL|#define FULL|g' $DIR/FirmAFL/qemu_mode/DECAF_qemu_2.10/zyw_config1.h
fi

echo "[*] Building system mode firmafl"
cd $DIR/FirmAFL/qemu_mode/DECAF_qemu_2.10/
./configure \
    --target-list=mipsel-softmmu,mips-softmmu,arm-softmmu \
    --disable-werror && \
    make

echo "[*] Building FirmaDyne"
cd $DIR/FirmAFL
git clone --recursive https://github.com/firmadyne/firmadyne.git
cd firmadyne

echo "[|] Getting/Building BinWalk"
git clone https://github.com/ReFirmLabs/binwalk.git
cd binwalk
sudo ./deps.sh --yes
reset
sudo python3 ./setup.py install
sudo pip3 install git+https://github.com/ahupp/python-magic
sudo pip3 install git+https://github.com/sviehb/jefferson
cd ..

echo "[|] Setting up Sasquatch Fork"
git clone https://github.com/firmadyne/sasquatch.git
cd sasquatch
make && sudo make install
cd ..

echo "[|] Setting up PostgreSQL"
service postgresql start

# Required, as the createuser script does not allow setting the password via echo+pipe
echo "CREATE USER firmadyne WITH ENCRYPTED PASSWORD 'firmadyne';" | sudo -u postgres psql
sudo -u postgres createdb -O firmadyne firmware
# sudo -u postgres psql -d firmware < ./database/schema # This is the empty default schema, we do not want this 

# Instead, import the original database, so program ids match
wget https://zenodo.org/record/4922202/files/data.xz
unxz data.xz
sudo -u postgres psql -d firmware < data 

echo "[|] Downloading Firmadyne additional binaries"
./download.sh

# Time for FirmAFL specific firmadyne adjustments
echo "[|] Applying FirmAFL specific patches"
cd $DIR/FirmAFL
cp ./firmadyne_modify/makeImage.sh ./firmadyne/scripts/
sed -i "s|#FIRMWARE_DIR=/home/vagrant/firmadyne/|FIRMWARE_DIR=$FIRMADYNE_DIR|" $FIRMADYNE_DIR/firmadyne.config
