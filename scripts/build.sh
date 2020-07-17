#!/usr/bin/env bash

# Stop script on NZEC
set -e
# Stop script if unbound variable found (use ${var:-} if intentional)
set -u
# By default cmd1 | cmd2 returns exit code of cmd2 regardless of cmd1 success
# This is causing it to fail
set -o pipefail


# Use in the the functions: eval $invocation
invocation='say_verbose "Calling: ${yellow:-}${FUNCNAME[0]} ${green:-}$*${normal:-}"'

# standard output may be used as a return value in the functions
# we need a way to write text on the screen in the functions so that
# it won't interfere with the return value.
# Exposing stream 3 as a pipe to standard output of the script itself
exec 3>&1

# Setup some colors to use. These need to work in fairly limited shells, like the Ubuntu Docker container where there are only 8 colors.
# See if stdout is a terminal
if [ -t 1 ] && command -v tput > /dev/null; then
    # see if it supports colors
    ncolors=$(tput colors)
    if [ -n "$ncolors" ] && [ $ncolors -ge 8 ]; then
        bold="$(tput bold       || echo)"
        normal="$(tput sgr0     || echo)"
        black="$(tput setaf 0   || echo)"
        red="$(tput setaf 1     || echo)"
        green="$(tput setaf 2   || echo)"
        yellow="$(tput setaf 3  || echo)"
        blue="$(tput setaf 4    || echo)"
        magenta="$(tput setaf 5 || echo)"
        cyan="$(tput setaf 6    || echo)"
        white="$(tput setaf 7   || echo)"
    fi
fi

say_warning() {
    printf "%b\n" "${yellow:-}build: Warning: $1${normal:-}"
}

say_err() {
    printf "%b\n" "${red:-}build: Error: $1${normal:-}" >&2
}

say() {
    # using stream 3 (defined in the beginning) to not interfere with stdout of functions
    # which may be used as return value
    printf "%b\n" "${cyan:-}build:${normal:-} $1" >&3
}

say_verbose() {
    if [ "$verbose" = true ]; then
        say "$1"
    fi
}

# args:
# input - $1
to_lowercase() {
    #eval $invocation

    echo "$1" | tr '[:upper:]' '[:lower:]'
    return 0
}

build_project () {
    eval $invocation

    host=""
    dev_version=""
    if [ -z "$version" ]
    then
        if [ -f "$repository_root_dir/.dev-host" ]; then
            host=$(cat $repository_root_dir/.dev-host)
        else
            host=$(hostname)
        fi

        if [ -f "$project_root_dir/.dev-version" ]; then
            dev_version=$(cat $project_root_dir/.dev-version)
            if [ "$skip_service_build" = false ]; then
                dev_version=$((dev_version + 1))
            fi
            version="0.1.1-dev.$host.$dev_version"
        else
            dev_version="1"
            version="0.1.1-dev.$host.$dev_version"
        fi
    fi

    if [ "$skip_service_build" = false ]; then
        say "Building $project $version"

        say_verbose "Running script: $script_dir"
        say_verbose "Project dir: $project_root_dir"

        say "Docker build:"
        say_verbose "Running: docker build --build-arg VERSION=$version -t $registry_full_name/$project_image_name:$version -f "$project_root_dir/Dockerfile" $docker_build_cwd"
        docker build --build-arg VERSION=$version -t $project_image_name:$version -f "$project_root_dir/Dockerfile" $docker_build_cwd
        docker tag $project_image_name:$version $project_image_name:latest

        if [ -n "$dev_version" ]; then
            say_verbose "Updating .dev-version to $dev_version."
            echo "$dev_version" > $project_root_dir/.dev-version
        fi
    fi

            
    if [ "$skip_service_push" = false ]; then
        docker tag $project_image_name:$version $registry_full_name/$project_image_name:$version

        say "Docker push:"

        say "Authenticating docker to access $registry_name ...\n"
        az acr login --name $registry_name

        docker push $registry_full_name/$project_image_name:$version
    fi


    say "Package helm chart:"
    say_verbose "Running: helm package --version $version --app-version $version --destination $repository_root_dir/out $chart"
    helm package --version $version --app-version $version --destination $repository_root_dir/out $chart

    if [ "$skip_upgrade" = false ]; then
        say_verbose "Running: helm upgrade --install $deployment_name $repository_root_dir/out/$deployment_name-$version.tgz --set image.repository=$registry_full_name/$project_image_name $values_file"
        helm upgrade --install $deployment_name $repository_root_dir/out/$deployment_name-$version.tgz --set image.repository=$registry_full_name/$project_image_name $values_file
    fi
}

args=("$@")

version=""
registry_name=""
registry_full_name=""
values_file=""
verbose=false
skip_upgrade=false
skip_service_build=false
skip_service_push=false

say_verbose "Setting script dir"
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
say_verbose "Setting script"
script=$script_dir/$( basename "${BASH_SOURCE[0]}" )
say_verbose "Setting repository root dir"
repository_root_dir=$(cd "$script_dir/../"; pwd)
project="Echo"
say_verbose "Setting project image name"
project_image_name=$(to_lowercase ${project//\./\-})
say_verbose "Setting project root dir"
project_root_dir=$(cd "$repository_root_dir/$project/"; pwd)
say_verbose "Setting docker build cwd"
docker_build_cwd=$(cd "$repository_root_dir/"; pwd)
say_verbose "Setting chart dir"
chart=$(cd "$project_root_dir/charts/$project_image_name"; pwd)
deployment_name="$project_image_name"

while [ $# -ne 0 ]
do
    name="$1"
    case "$name" in
        -r|--registry|-[Rr]egistry)
            shift
            registry_name="$1"
            registry_full_name="$1.azurecr.io"
            ;;
        -v|--version|-[Vv]ersion)
            shift
            version="$1"
            ;;
        -f|--file|-[Ff]file)
            shift
            values_file="-f $1"
            ;;
        --verbose|-[Vv]erbose)
            verbose=true
            non_dynamic_parameters+=" $name"
            ;;
        --skip-upgrade)
            skip_upgrade=true
            non_dynamic_parameters+=" $name"
            ;;        
        --skip-build)
            skip_service_build=true
            non_dynamic_parameters+=" $name"
            ;;        
        --skip-push)
            skip_service_push=true
            non_dynamic_parameters+=" $name"
            ;;
        *)
            say_err "Unknown argument \`$name\`"
            exit 1
            ;;
    esac

    shift
done

build_project