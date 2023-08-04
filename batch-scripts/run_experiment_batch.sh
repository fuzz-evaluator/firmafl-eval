#!/bin/bash

if [ $# -ne 3 ]; then
    echo "usage: $0 <config_id_file> <num_iterations> <seconds_per_experiment>"
    exit 1
fi

config_id_file="$1"
num_iterations="$2"
seconds_per_experiment="$3"

if [ ! -f "$config_id_file" ]; then 
    echo "Config file $config_id_file does not exist"
    exit 2
fi

for config_id in $(cat $config_id_file); do
    echo "Next config id: $config_id"

    for docker_image in firmafl firmafl-full firmafl-full-afl2.52b ; do
        for i in $(seq 1 $num_iterations); do
            container_name="$docker_image-config-$config_id-run-$i-duration-$seconds_per_experiment"
            docker rm -f $container_name &>/dev/null
            docker run --detach --privileged --entrypoint /workspaces/firmafl-repro/run_experiment.sh --name $container_name $docker_image $config_id $seconds_per_experiment
            # Give the fuzzer some time to bind to a core
            sleep 60
        done
    done
done

# AFL queue directory: /workspaces/firmafl-repro/FirmAFL/image_${config_id}/outputs
