#! /bin/bash
# Backup script for www.samhobbs.co.uk

# USE FULL PATH
BACKUP_DIR="/media/backup/website/"
DRUPAL_DIR="/var/www/samhobbs/"
ENCRYPTION_KEYWORDFILE="/home/sam/.mcryptpasswordfile"

# External email address to send monthly encrypted backup files to
EXTERNAL_EMAIL="you@yourexternalemail.com"

# redirect errors and output to log file
exec 2>&1 1>>"${BACKUP_DIR}backup-log.txt"

NOW=$(date +"%Y-%m-%d")


# Headers for log
echo ""
echo "#==================================================== $NOW ====================================================#"
echo ""

# Back up Drupal with Drush
drush archive-dump default -r $DRUPAL_DIR --tar-options="-z" --destination=$BACKUP_DIR$NOW.tar.gz

# clean up old backup files
# we want to keep:
#               one week of daily backups
#               one month of weekly backups (1st, 8th, 15th and 22nd)
#               monthly backups for one year
#               yearly backups thereafter

# seconds since epoch (used for calculating file age)
SSE=$(date +%s)

FILES_LIST=( "$BACKUP_DIR"* )

for file in "${FILES_LIST[@]}"; do
  if [[ $file = *20[0-9][0-9]-[0-9][0-9]-[0-9][0-9].tar.gz ]]; then
    FILENAME=$(basename "$file")
    FILENAME_NO_EXTENSION=${FILENAME%%.*}
    FILE_YEAR=$(echo $FILENAME_NO_EXTENSION | cut -d'-' -f 1)
    FILE_MONTH=$(echo $FILENAME_NO_EXTENSION | cut -d'-' -f 2)
    FILE_DAY=$(echo $FILENAME_NO_EXTENSION | cut -d'-' -f 3)
    SSE_FILE=$(date -d "$FILE_YEAR$FILE_MONTH$FILE_DAY" +%s)
    AGE=$((($SSE - $SSE_FILE)/(24*60*60))) # age in days

    # if file is from the first day of a year (yearly backup), skip it
    if [[ $file = *20[0-9][0-9]-01-01.tar.gz ]]; then
      echo "file $file is a yearly backup: keeping"

    # if file is from the first day of a month (monthly backup) and age is less than 365 days, skip it
    elif [[ $file = *20[0-9][0-9]-[0-9][0-9]-01.tar.gz ]] && [ $AGE -lt 365 ]; then
      echo "file $file is a monthly backup, age < 1yr: keeping"

    # if day of month is 08, 15 or 22 (weekly backup) and age is less than 30 days, skip it
    elif [ $FILE_DAY -eq 08 -o $FILE_DAY -eq 15 -o $FILE_DAY -eq 22 ] && [ $AGE -lt 30 ]; then
      echo "file $file is a weekly backup, age < 30 days: keeping"

    # if age is less than seven days, skip it
    elif [ $AGE -lt 7 ]; then
      echo "file $file is a daily backup, age < 7 days: keeping"

    # if it hasn't matched one of the above, it should be deleted
    else
      echo "removing file $file"
      rm $file
    fi
  else
    echo "file $file does not match the expected pattern: skipping"
  fi
done

DAY=$(date +%d)

if [[ $DAY = 01 ]]; then
  echo "encrypting a copy of today's backup to send by email"
  # encrypt today's backup file using mcrypt
  mcrypt -F -f $ENCRYPTION_KEYWORDFILE $BACKUP_DIR$NOW.tar.gz

  # if the encryption is successful, email the file to an external email address
  if [[ -f $BACKUP_DIR$NOW.tar.gz.nc ]]; then
    echo "Monthly backup created $NOW, encrypted using mcrypt" | mutt -s "Monthly backup" -a $BACKUP_DIR$NOW.tar.gz.nc -- $EXTERNAL_EMAIL
    echo "Email sent, removing encrypted file"
    rm $BACKUP_DIR$NOW.tar.gz.nc
    echo "Done"
  else
    echo "Something went wrong with mcrypt: the encrypted file was not found"
    exit 1
  fi
fi
