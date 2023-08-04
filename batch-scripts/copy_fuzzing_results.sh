#!/bin/bash

DIR="$(dirname "$(readlink -f "$0")")"

if [ $# -ne 3 ]; then
    echo "usage: $0 <config_id_file> <num_iterations> <seconds_per_experiment>"
    exit 1
fi

output_base_dir="$DIR/../../firmafl-outputs"

config_id_file="$1"
num_iterations="$2"
seconds_per_experiment="$3"

if [ ! -f "$config_id_file" ]; then
    echo "Config file $config_id_file does not exist"
    exit 2
fi

if [ -e "$output_base_dir" ]; then
    echo "Output base dir exists. Please delete it first: rm -rf $output_base_dir"
    exit 3
fi

for config_id in $(cat $config_id_file); do
    echo "Next config id: $config_id"

    for docker_image in firmafl firmafl-full firmafl-fair; do
        for i in $(seq 1 $num_iterations); do
            container_name="$docker_image-config-$config_id-run-$i-duration-$seconds_per_experiment"
            # echo docker rm -f $container_name
            # echo docker run --detach --privileged --entrypoint /workspaces/firmafl-repro/run_experiment.sh --name $container_name $docker_image $config_id $seconds_per_experiment
            # Give the fuzzer some time to bind to a core

            local_output_dir="$output_base_dir/$container_name"
            mkdir -p "$local_output_dir"

            docker cp $container_name:/workspaces/firmafl-repro/FirmAFL/image_${config_id}/outputs "$local_output_dir" &>/dev/null
            docker cp $container_name:/workspaces/firmafl-repro/FirmAFL/image_${config_id}/outputs_full "$local_output_dir" &>/dev/null
            # docker cp $container_name:/workspaces/firmafl-repro/FirmAFL/image_${config_id} /tmp/tmp_fuzzing_results
            echo "-- $container_name --"
            ls $local_output_dir/out*
        done
    done
    echo
done

# AFL queue directory: /workspaces/firmafl-repro/FirmAFL/image_${config_id}/outputs