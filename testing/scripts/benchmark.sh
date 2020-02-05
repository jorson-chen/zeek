#!/bin/sh

ZEEK_BUILD=/mnt/data/tim/builds/master/bin/zeek
DATA_FILE=/mnt/data/test_data/ixia_data_2m_600Mbps.pcap
MODE="benchmark"

# Path where flamegraph is installed
FLAMEGRAPH_PATH=/usr/local/FlameGraph

# CPUs to pin processes to
ZEEK_CPU=10
TCPREPLAY_CPU=11

while (( "$#" )); do
  case "$1" in
      -d|--data-file)
	  DATA_FILE=$2
	  shift 2
	  ;;
      -b|--build)
	  ZEEK_BUILD=$2
	  shift 2
	  ;;
      -f|--flame-graph)
	  MODE="flamegraph"
	  FG_FILE=$2
	  shift 2
	  ;;
  esac
done

ZEEK_ARGS="-i af_packet::ens1f0"

echo "Running '${ZEEK_BUILD} ${ZEEK_ARGS}' against ${DATA_FILE}"

if [ "${MODE}" = "benchmark" ]; then

    TIME_FILE=$(mktemp)

    # Start zeek, find it's PID, then wait 10s to let it reach a steady state
    taskset --cpu-list $ZEEK_CPU time -f "%M" -o ${TIME_FILE} $ZEEK_BUILD $ZEEK_ARGS &
    TIME_PID=$!

    sleep 10

    ZEEK_PID=$(ps -ef | awk -v timepid="${TIME_PID}" '{ if ($3 == timepid) { print $2 } }')
    echo "Zeek running on PID ${ZEEK_PID}"

    # Start perf stat on the zeek process
    perf stat -p ${ZEEK_PID} &
    PERF_PID=$!

    # Start replaying the data
    echo "Starting replay"
    taskset --cpu-list $TCPREPLAY_CPU tcpreplay -i ens1f0 -q $DATA_FILE

    # TODO: does it make sense to sleep here to let zeek finish processing all of the packets
    # out of the kernel buffer?

    # Print the average CPU usage of the process
    echo
    CPU_USAGE=$(ps -p $ZEEK_PID -o %cpu=)

    # Kill everything
    kill -2 $ZEEK_PID
    wait $TIME_PID
    wait $PERF_PID

    echo "Maximum memory usage (max_rss): $(head -n 1 ${TIME_FILE}) bytes"
    echo "Average CPU usage: ${CPU_USAGE}%"

    rm $TIME_FILE

elif [ "${MODE}" = "flamegraph" ]; then

    PERF_RECORD_FILE=$(mktemp)

    # Start zeek under perf record, then sleep for a few seconds to let it actually start up
    taskset --cpu-list $ZEEK_CPU perf record -g -c 499 -o $PERF_RECORD_FILE -- $ZEEK_BUILD $ZEEK_ARGS &
    PERF_PID=$!

    sleep 5

    ZEEK_PID=$(ps -ef | awk -v perfpid="${PERF_PID}" '{ if ($3 == perfpid) { print $2 } }')
    echo "Zeek running on PID ${ZEEK_PID}"
    echo

    # Start replaying the data
    echo "Starting replay"
    tcpreplay -i ens1f0 -q $DATA_FILE

    # Kill everything
    echo
    kill -2 $ZEEK_PID
    wait $PERF_PID

    echo
    echo "Building SVG for output"
    perf script -i $PERF_RECORD_FILE | ${FLAMEGRAPH_PATH}/stackcollapse-perf.pl | ${FLAMEGRAPH_PATH}/flamegraph.pl > ${FG_FILE}
#    rm $PERF_RECORD_FILE

fi
