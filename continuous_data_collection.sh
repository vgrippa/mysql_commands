#!/bin/bash
# EDIT THESE TO MATCH YOUR ENVIRONMENT
# make sure the PTDEST folder has plenty of space
PTDEST="${HOME}/$(hostname)";
MYSQL_USER="msandbox";
MYSQL_PASS="msandbox";
MYSQL_SOCK="/tmp/mysql_sandbox5730.sock";
cat << EOT > ${HOME}/.support.cnf
[client]
user=${MYSQL_USER}
password=${MYSQL_PASS}
socket=${MYSQL_SOCK}
EOT
chmod 0600 ${HOME}/.support.cnf; # only user creating the file can read it
MYSQL="mysql --defaults-file=${HOME}/.support.cnf";
MYSQLADMIN="mysqladmin --defaults-file=${HOME}/.percona-support.cnf";
MYSQL_PID=$(pgrep -x mysqld -n); # newest mysqld pid
[ -d "${PTDEST}" ] || mkdir -p ${PTDEST};
cd /tmp/;
[[ -f "/tmp/pt-summary" ]] || wget percona.com/get/pt-{summary,mysql-summary} > /tmp/pt-downloads.log 2>&1;
chmod +x pt*;
sudo ./pt-summary > "${PTDEST}/pt-summary.out";
sudo ./pt-mysql-summary --defaults-file=${HOME}/.percona-support.cnf --save-samples="${PTDEST}/samples"  > "${PTDEST}/pt-mysql-summary.out";
sudo lsblk --all > "${PTDEST}/lsblk-all";
smartctl --scan |awk '{print $1}'|while read device; do { sudo smartctl --xall "${device}"; } done > "${PTDEST}/smartctl.out";
sudo multipath -ll > "${PTDEST}/multipath_ll";
sudo nfsstat -m > "${PTDEST}/nfsstat_m";
sudo nfsiostat 1 120 > "${PTDEST}/nfsiostat";
sudo dmesg >  "${PTDEST}/dmesg";
sudo dmesg -T >  "${PTDEST}/dmesg_T";
sudo ulimit -a > "${PTDEST}/ulimit_a";
sudo cat /proc/${MYSQL_PID}/limits > "${PTDEST}/proc_${MYSQL_PID}_limits";
sudo numactl --hardware  >  "${PTDEST}/numactl-hardware";
sudo sysctl -a > "${PTDEST}/sysctl_a";
sudo pgrep -x mysqld > "${PTDEST}/mysqld_PIDs";
rm -f /tmp/exit-monitor 2>/dev/null;
while true; do {

  d=$(date +%F_%T |tr ":" "-");
  echo ${d} >> ${PTDEST}/samples_list;
  echo "Collecting sample ${d}...";
  MYSQL_PID=$(pgrep -x mysqld -n); # newest mysqld pid

  for i in {1..60}; do {
    echo -n "."
    [ -f /tmp/exit-percona-monitor ] && echo "exiting loop (/tmp/exit-percona-monitor is there)" && break;

    TS=$(date +"TS %s %F %T");
    # TCP and general network metrics
    echo "$TS" >> ${PTDEST}/${d}-netstat_s;
    netstat -s >> ${PTDEST}/${d}-netstat_s &

    # extended processlist which includes background threads
    echo "$TS" >> ${PTDEST}/${d}-threads;
    $MYSQL -e "SELECT * FROM performance_schema.threads\G" >> ${PTDEST}/${d}-threads &

    # lock contention information
    echo "$TS" >> ${PTDEST}/${d}-innodb_lock_waits;
    $MYSQL -e "SELECT * FROM sys.innodb_lock_waits\G" >> ${PTDEST}/${d}-innodb_lock_waits &

    if [[ $((i%20)) -eq "0" ]]; then {
      # CPU profiling; 10s 3 times per minute at 99Hz; Uncomment if you feel it's safe.
      # sudo perf record -a -g -F99 -p $MYSQL_PID -o ${PTDEST}/${d}-${i}-perf.data -- sleep 10 &

      # InnoDB status snapshot
      $MYSQL -e "SHOW ENGINE INNODB STATUS\G" > ${PTDEST}/${d}-innodbstatus${i} &
    } fi;

    sleep 1;
  } done &


  # global virtual memory and CPU information
  vmstat 1 60 > ${PTDEST}/${d}-vmstat &

  # IO metrics
  iostat -dmx 1 60 > ${PTDEST}/${d}-iostat &

  # per-core virtual memory and CPU information
  mpstat -u -P ALL 1 60 > ${PTDEST}/${d}-mpstat &

  # per process context switches information
  # pidstat -w 10 6 > ${PTDEST}/${d}-pidstat_d &

  # per process IO throughput information
  # pidstat -d 1 60 > ${PTDEST}/${d}-pidstat_d &

  # MySQL metrics (equivalent to SHOW GLOBAL STATUS; Uses same underlying code)
  $MYSQLADMIN -i1 -c60 ext > ${PTDEST}/${d}-mysqladmin &

  # Network device metrics
  sar -n DEV 1 60 > ${PTDEST}/${d}-sar_dev &
  sleep 60;

  # set retention, in days, with -mtime
  find $PTDEST -mtime +1 -delete -print >> $PTDEST/purge.log;
} done;
# uncomment if you capture perf
 for i in $PTDEST/*-perf.data; do {
   echo "processing $i into $i.script...";
   sudo perf script -i $i > $i.script;
 } done
