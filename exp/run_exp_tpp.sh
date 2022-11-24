#!/bin/bash

RESULT_DIR="/ssd1/songxin8/thesis/xgboost/ecosys_xgboost/exp/exp_tpp/"
DATA_DIR="/ssd1/songxin8/thesis/xgboost/ecosys_xgboost/demo/criteo_1tb/" 
XGBOOST_EXE="/ssd1/songxin8/thesis/xgboost/ecosys_xgboost/xgboost"

clean_up () {
    echo "Cleaning up. Kernel PID is $EXE_PID, numastat PID is $NUMASTAT_PID."
    # Perform program exit housekeeping
    kill $EXE_PID
    kill $NUMASTAT_PID
    kill $TOP_PID
    exit
}

clean_cache () { 
  echo "Clearing caches..."
  # clean CPU caches 
  ./tools/clear_cpu_cache
  # clean page cache
  echo 3 > /proc/sys/vm/drop_caches
}

enable_tpp () {
  sudo service numad stop
  NUMAD_OUT=$(systemctl is-active numad)
  echo "numad service is now $NUMAD_OUT (should be inactive)"

  echo 15 > /proc/sys/vm/zone_reclaim_mode
  echo 2 > /proc/sys/kernel/numa_balancing
  echo 1 > /sys/kernel/mm/numa/demotion_enabled
  echo 200 > /proc/sys/vm/demote_scale_factor

  # read back
  ZONE_RECLAIM_MODE=$(cat /proc/sys/vm/zone_reclaim_mode)
  NUMA_BALANCING=$(cat /proc/sys/kernel/numa_balancing)
  DEMOTION_ENABLED=$(cat /sys/kernel/mm/numa/demotion_enabled)
  DEMOTE_SCALE_FACTOR=$(cat /proc/sys/vm/demote_scale_factor)
  echo "Kernel parameters: "
  echo "ZONE_RECLAIM_MODE $ZONE_RECLAIM_MODE (15)"
  echo "NUMA_BALANCING $NUMA_BALANCING (2)"
  echo "DEMOTION_ENABLED $DEMOTION_ENABLED (1)"
  echo "DEMOTE_SCALE_FACTOR $DEMOTE_SCALE_FACTOR (200)"
}

enable_autonuma () {
  # numad will override autoNUMA, so stop it
  sudo service numad stop
  NUMAD_OUT=$(systemctl is-active numad)
  echo "numad service is now $NUMAD_OUT (should be inactive)"

  echo 2 > /proc/sys/kernel/numa_balancing
  NUMA_BALANCING=$(cat /proc/sys/kernel/numa_balancing)
  echo "numa_balancing is now $NUMA_BALANCING (should be 1)"
}

disable_autonuma () {
  # turn off both numa
  sudo service numad stop
  NUMAD_OUT=$(systemctl is-active numad)
  echo "numad service is now $NUMAD_OUT (should be not active)"

  echo 0 > /proc/sys/vm/zone_reclaim_mode
  echo 0 > /proc/sys/kernel/numa_balancing
  NUMA_BALANCING=$(cat /proc/sys/kernel/numa_balancing)
  echo "numa_balancing is now $NUMA_BALANCING (should be 0)"
}


run_exp () { 
  OUTFILE=$1 #first argument
  MEM_CONFIG=$2

  TIME_COMMON="/usr/bin/time -v "

  if [[ "$MEM_CONFIG" == "ALL_LOCAL" ]]; then
    # All local config: place both data and compute on node 1
    NUMA_COMMON=" /usr/bin/numactl --membind=1 --cpunodebind=1"
  elif [[ "$MEM_CONFIG" == "AUTONUMA" ]]; then
    NUMA_COMMON=" /usr/bin/numactl --cpunodebind=0"
  elif [[ "$MEM_CONFIG" == "TPP" ]]; then
    NUMA_COMMON=" /usr/bin/numactl --cpunodebind=0"
  else
    echo "Error! Undefined configuration $MEM_CONFIG"
    exit 1
  fi

  echo "Start" > $OUTFILE

  pushd ${DATA_DIR}
  ${TIME_COMMON} ${NUMA_COMMON} ${XGBOOST_EXE} ${DATA_DIR}/criteo.conf &>> $OUTFILE &
  popd

  # PID of time command
  TIME_PID=$! 
  # get PID of actual kernel, which is a child of time. 
  # This PID is needed for the numastat command
  EXE_PID=$(pgrep -P $TIME_PID)

  echo "EXE PID is ${EXE_PID}"
  echo "start" > ${OUTFILE}_numastat 
  while true; do numastat -p $EXE_PID >> ${OUTFILE}_numastat; sleep 5; done &
  NUMASTAT_PID=$!
  top -b -d 20 -1 -p $EXE_PID > ${OUTFILE}_top_log &
  TOP_PID=$!

  echo "Waiting for workload to complete (PID is ${EXE_PID}). numastat is logged into ${OUTFILE}_numastat, PID is ${NUMASTAT_PID}. Top PID is ${TOP_PID}" 
  wait $TIME_PID
  echo "workload complete."
  kill $NUMASTAT_PID
  kill $TOP_PID
}


##############
# Script start
##############
trap clean_up SIGHUP SIGINT SIGTERM

[[ $EUID -ne 0 ]] && echo "This script must be run using sudo or as root." && exit 1

mkdir -p $RESULT_DIR

# All allocations on node 0
disable_autonuma
clean_cache
run_exp "${RESULT_DIR}/criteo1TB_alllocal" "ALL_LOCAL"

## TPP
#enable_tpp
#clean_cache
#run_exp "${RESULT_DIR}/criteo1TB_tpp" "TPP"

## AutoNUMA
#enable_autonuma 
#clean_cache
#run_exp "${RESULT_DIR}/criteo1TB_autonuma" "AUTONUMA"
