#!/bin/bash

python -u higgs-numpy.py
ret=$?
if [[ $ret != 0 ]]; then
    echo "ERROR in higgs-numpy.py"
    exit $ret
fi
