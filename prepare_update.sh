#!/bin/bash
rm controls.txt
while IFS= read -r -d '' FILE
do
  TIME=$(git log --pretty=format:%cd -n 1 --date=iso -- "$FILE")
  TIME=$(TZ=Europe/Berlin date -d "$TIME" +%Y-%m-%d_%H:%M:%S)
  FILESIZE=$(stat -c%s "$FILE")
	FILE=$(echo "$FILE"  | cut -c 3-)
	#printf "DEL %s\n" "$FILE"  >> controls.txt
	printf "UPD %s %-7d %s\n" "$TIME" "$FILESIZE" "$FILE"  >> controls.txt
done <   <(find ./FHEM -maxdepth 2 \( -name "*.pm" -o -name "*.txt" \) -print0 | sort -z -g)

# CHANGED file
echo "FHEM Grohe Ondus last changes:" > CHANGED
echo $(date +"%Y-%m-%d") >> CHANGED
echo " - $(git log -1 --pretty=%B)" >> CHANGED
