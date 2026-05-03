#!/bin/sh
# FishFish Payload — executed once per injected filesystem
# Environment provided by framework:
#   FF_MOUNTPOINT  FF_DEVICE  FF_FSTYPE  FF_UUID  FF_LABEL

set -e

# MVP: proof-of-access marker file
touch "INJECTION_SUCCESS.txt"
