#!/bin/bash


#TODO: add --timeout_seconds=
# import common functions
if [ "$BIGMEMBENCH_COMMON_PATH" = "" ] ; then
  echo "ERROR: bigmembench_common script not found. BIGMEMBENCH_COMMON_PATH is $BIGMEMBENCH_COMMON_PATH"
  echo "Have you set BIGMEMBENCH_COMMON_PATH correctly? Are you using sudo -E instead of just sudo?"
  exit 1
fi
source ${BIGMEMBENCH_COMMON_PATH}/run_exp_common.sh

RESULT_DIR="exp/exp_lfu_07272023/"

MEMCONFIG="16threads"
NUM_ITERS=3

HOOK_SO="/ssd1/songxin8/thesis/bigmembench_common/hook/hook.so"

PERF_STAT_INTERVAL=10000

run_app () {
  OUTFILE_NAME=$1 
  CONFIG=$2

  OUTFILE_PATH="${RESULT_DIR}/${OUTFILE_NAME}"

  COMMAND_COMMON=$(get_cmd_prefix $CONFIG)

  write_frontmatter $OUTFILE_PATH

  echo "XGBoost config file ========================" >> $OUTFILE_PATH
  cat ./train.dev.conf >> $OUTFILE_PATH
  echo "XGBoost config file end ========================" >> $OUTFILE_PATH

  start_perf_stat $PERF_STAT_INTERVAL $OUTFILE_PATH
  echo "2 perf stat pid is $PERF_STAT_PID"


  if [[ "$CONFIG" == "LFU" ]]; then
    export LD_PRELOAD=${HOOK_SO}
  else
    export LD_PRELOAD=
  fi

  echo "LD_PRELOAD is $LD_PRELOAD"
  echo "${COMMAND_COMMON} ./xgboost ./train.dev.conf &>> $OUTFILE_PATH" >> $OUTFILE_PATH

  ${COMMAND_COMMON} ./xgboost ./train.dev.conf &>> $OUTFILE_PATH
  # stop trapping since a lot of commands use __libc_start_main
  export LD_PRELOAD=

  write_backmatter $OUTFILE_PATH
  kill_perf_stat
}


##############
# Script start
##############

mkdir -p $RESULT_DIR


# AutoNUMA
for ((i=0;i<$NUM_ITERS;i++));
do
  enable_autonuma "MGLRU"
  clean_cache
  LOGFILE_NAME=$(gen_file_name "xgboost" "_" "${MEMCONFIG}_autonuma" "iter$i")
  run_app $LOGFILE_NAME "AUTONUMA"
done

# TinyLFU
for ((i=0;i<$NUM_ITERS;i++));
do
  enable_lfu
  clean_cache
  LOGFILE_NAME=$(gen_file_name "xgboost" "_" "${MEMCONFIG}_lfu" "iter$i")
  run_app $LOGFILE_NAME "LFU"
done

## All allocations on local
#for ((i=0;i<$NUM_ITERS;i++));
#do
#  disable_numa
#  clean_cache
#  LOGFILE_NAME=$(gen_file_name "xgboost" "_" "${MEMCONFIG}_allLocal" "iter$i")
#  run_app $LOGFILE_NAME "ALL_LOCAL"
#done

