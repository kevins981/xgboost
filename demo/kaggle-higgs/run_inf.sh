#!/bin/bash

python -u higgs-pred.py
ret=$?
if [[ $ret != 0 ]]; then
    echo "ERROR in higgs-pred.py"
    exit $ret
fi
