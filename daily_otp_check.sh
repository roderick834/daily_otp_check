#!/bin/bash

jq_bin=$(which jq);
usage() {
  echo "Usage: $0 -d domain"
  exit 1
}

#get domain from the string and hint usage

while getopts "d:" opt; 
do
  case ${opt} in
    d)
      d_domain=$OPTARG
      ;;
    *)
      usage
      ;;
  esac
done

#check domain is available
if [ -z "$d_domain" ]; 
then
  echo "[ERROR] Missing domain"
  usage
fi

if !  /webmail/tools/alldomain|grep -q $d_domain ;
then
  echo "[ERROR] Domain : $d_domain not found" ;
  usage
fi


#export mongo data to json and query disable user to csv file
mongo_domain=$(echo $d_domain|sed 's/\./\_/g') ;
json_file="/home/webmail/daily_otp_check/otp_info_$mongo_domain.json" ;
csv_attach_file="/home/webmail/daily_otp_check/attach.csv" ;
mongoexport --host 127.0.0.1 --db "$mongo_domain" --collection user_otp_info --out "/home/webmail/daily_otp_check/otp_info_$mongo_domain.json"
mongoexport --host 127.0.0.1 --db "$mongo_domain" --collection user_otp_info --query '{"OTPMode": 0}' --type=csv --out="$csv_attach_file" --fields=userID,OTPMode
bcsv_attach_file=$(base64 $csv_attach_file | tr -d '\n') ;

#check json file
if [ ! -f "$json_file" ]; 
then
  echo "[ERROR] JSON file not found" ;
  exit 1
fi


#generate eml
get_radm=`/webmail/tools/admscan -s -c summary |awk '{print $2}'|grep $d_domain | tr '\n' ',' | sed 's/,$//'`;
ann_date="$(date +"Date: %a, %d %b %Y %T %z")" ;
get_dadm=`/webmail/tools/default_adm_get`;
output_file="/home/webmail/daily_otp_check/daily.check.report.$d_domain" ;
filter_json=$($jq_bin -s '. | map(select(.OTPMode == 0)) | .[] | "<tr><td> \(.userID)</td><td>\(.OTPMode)</td></tr>"' $json_file |sed 's/^"\(.*\)"$/\1/' |wc -l )
echo "From: $get_dadm
To: $get_radm
Subject: =?utf-8?B?W+ezu+e1semAmuefpV3mnKrplovllZ/pm5nph43oqo3orYnlkI3llq4K?=
$ann_date
MIME-Version: 1.0
X-Charset: utf-8" > $output_file ;
echo -e 'Content-Type: multipart/mixed; 
                boundary="---e9iunZvQf.+AD4iwW4y2=njyHDk"' "\n" >>$output_file ;
echo -e '-----e9iunZvQf.+AD4iwW4y2=njyHDk
Content-Type: multipart/alternative;
        boundary="---X=pWY?HJA3m1IsMzH+)WPmbL/xy"' "\n" >>$output_file ;
echo -e '-----X=pWY?HJA3m1IsMzH+)WPmbL/xy
Content-Type: text/html; charset=utf-8
Content-Transfer-Encoding: quoted-printable' "\n">> $output_file ;
echo '<html>
<head>
<style>
        body {
            font-family: 'Arial', sans-serif;
            background-color: #f4f4f4;
            margin: 0;
            padding: 20px;
        }

        h1 {
            text-align: center;
            color: #333;
        }

        table {
            width: 80%;
            margin: 20px auto;
            border-collapse: collapse;
            box-shadow: 0 0 10px rgba(0, 0, 0, 0.1);
            border-radius: 10px;
            overflow: hidden;
        }

        th {
            background-color: #F8981D;
            color: white;
            padding: 12px;
            text-align: center;
            font-size: 16px;
        }

        td {
            background-color: #ffffff;
            color: #333;
            padding: 12px;
            text-align: center;
            border-top: 1px solid #ddd;
        }

        tr:hover {
            background-color: #f1f1f1;
        }

        td, th {
            border: 1px solid #ddd;
        }

        table {
            border-radius: 10px;
            overflow: hidden;
        }

    </style>
</head>
<body> 
<table>
        <thead>
            <tr>
                <th colspan="2"> Openfind Mail2000 OTP Report</th>

            </tr>' >> $output_file; 
echo "      <tr>
                <td style='border: none;'> Check Time : $ann_date </td>" >>$output_file ;
echo "          <td style='border: none;'>共計: $filter_json  筆</td>
           </tr>
            <tr>
                <th>UserID</th>
                <th>Mode</th>
            </tr>
        </thead>
        <tbody>" >> $output_file ;

jq -s '. | map(select(.OTPMode == 0)) | .[] | "<tr><td> \(.userID)</td><td>\(.OTPMode)</td></tr>"' $json_file |sed 's/^"\(.*\)"$/\1/'  >> $output_file ;

echo "</tbody>
</table>" >> $output_file ;
echo "</body>" >> $output_file ;
echo -e "</html>
-----X=pWY?HJA3m1IsMzH+)WPmbL/xy--" "\n" >> $output_file ;
echo '-----e9iunZvQf.+AD4iwW4y2=njyHDk
Content-Type: text/csv;
        name="disable_info.csv"
Content-Disposition: attachment;
        filename="disable_info.csv"
Content-Transfer-Encoding: base64' >> $output_file ;

echo -e "\n" $bcsv_attach_file "\n"  "\n" >> $output_file ;


echo '-----e9iunZvQf.+AD4iwW4y2=njyHDk--' >> $output_file ; 
echo "File generated: $output_file" ; 

for mbx_rc in `/webmail/tools/admscan -s -c summary |awk '{print $2}'|grep $d_domain` ;
do
/webmail/tools/mbx_import -T -n -d $mbx_rc @ $output_file ;
done
