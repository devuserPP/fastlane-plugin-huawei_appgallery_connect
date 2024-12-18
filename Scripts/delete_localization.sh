#!/usr/bin/env bash
# fail if any commands fail
set -e
# debug log
if [ "${show_debug_logs}" == "yes" ]; then
  set -x
fi

function getToken() {
  printf "\n\nObtaining a Token\n"
  
  curl --silent -X POST \
    https://connect-api.cloud.huawei.com/api/oauth2/v1/token \
    -H 'Content-Type: application/json' \
    -H 'cache-control: no-cache' \
    -d '{
      "grant_type": "client_credentials",
      "client_id": "'${huawei_client_id}'",
      "client_secret": "'${huawei_client_secret}'"
  }' > token.json

  printf "\nObtaining a Token ✅\n"
}

function deleteLocalizations() {
  ACCESS_TOKEN=$(jq -r '.access_token' token.json)

  # List of languages to delete
  LANGUAGES_TO_DELETE=("fil" "lt" "hr" "lv" "no-NO" "zh-CN" "el-GR" "nl-NL" "uk" "kn_IN" "ug_CN" 
    "hi-IN" "pa_Guru_IN" "id" "mk-MK" "ur" "ja-JP" "hu-HU" "te_IN" "ne-NP" "ka-GE" "uz" "ms" 
    "ta_IN" "am_ET" "eu-ES" "et" "ar" "pl-PL" "pt-PT" "vi" "tr-TR" "fa" "fr-FR" "ro" "en-GB" 
    "km-KH" "fi-FI" "az-AZ" "be" "bg" "mr_IN" "gl-ES" "jv" "mai_Deva_IN" "mn_MN" "bo" "sw_TZ" 
    "he_IL" "or_IN" "bs" "si-LK" "my-MM" "sk" "sl" "lo-LA" "cs-CZ" "iw-IL" "ca" "as_IN" "sr" 
    "kk" "de-DE" "zh-TW" "zh-HK" "ko-KR" "pt-BR" "es-ES" "te_TE" "it-IT" "ru-RU" "bn-BD" "th" 
    "gu_IN" "sv-SE" "ml_IN" "am-ET" "da-DK" "es-419" "mi_NZ")

  printf "\nDeleting Specific Localizations\n"

  for lang in "${LANGUAGES_TO_DELETE[@]}"; do
    printf "\nAttempting to delete localization: $lang\n"
    response=$(curl --silent -X DELETE \
      "https://connect-api.cloud.huawei.com/api/publish/v2/app-language-info?appId=${huawei_app_id}&lang=${lang}" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}" \
      -H "client_id: ${huawei_client_id}" \
      -H "Content-Type: application/json")

    # Parse response
    ret_code=$(echo "$response" | jq -r '.ret.code')
    ret_msg=$(echo "$response" | jq -r '.ret.msg')

    if [[ "$ret_code" == "0" ]]; then
      printf "\nDeleted localization: $lang ✅ - Response: $ret_msg\n"
    else
      printf "\nFailed to delete localization: $lang ❌ - Code: $ret_code, Message: $ret_msg\n"
    fi
  done

  printf "\nAll Specified Localizations Processed ✅\n"
}

# SET Environment Variables
export huawei_client_id="your_huawei_client_id"
export huawei_client_secret="your_huawei_client_secret"
export huawei_app_id="huawei_app_id"

# Execution Flow
getToken
deleteLocalizations

printf "\n🎉 All Specified Localizations Successfully Processed! 🎊\n"
exit 0
