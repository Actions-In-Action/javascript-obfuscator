#! /bin/bash

source "./assert.sh/assert.sh"

# check env
assert_not_empty "${SECRETS_PUSH_URL}"              "PUSH_URL"
assert_not_empty "${SECRETS_GITEE_USERNAME}"        "GITEE_USERNAME"
assert_not_empty "${SECRETS_GITEE_CLIENT_ID}"       "GITEE_CLIENT_ID"
assert_not_empty "${SECRETS_GITEE_CLIENT_SECRET}"   "GITEE_CLIENT_SECRET"
assert_not_empty "${SECRETS_GITEE_PASSWORD}"        "GITEE_PASSWORD"

GITEE_REPO=js

echo "fetching the latest build commit of javascript-obfuscator/javascript-obfuscator-ui"
github_latest_commit=$(curl -s https://api.github.com/repos/javascript-obfuscator/javascript-obfuscator-ui/commits | grep '"sha":' | head -1 | grep -oP "[a-f\d]{40}")
if [ -z "${github_latest_commit}" ]; then
    echo "fetch the latest build commit of javascript-obfuscator/javascript-obfuscator-ui failed"

    exit 1
fi
echo "the latest build commit of javascript-obfuscator/javascript-obfuscator-ui is ${github_latest_commit}"


echo "checking gitee tag"
if ! gitee_tag=$(curl --silent -X GET --header 'Content-Type: application/json;charset=UTF-8' "${SECRETS_PROXY_URL}https://gitee.com/api/v5/repos/${SECRETS_GITEE_USERNAME}/${GITEE_REPO}/tags"); then
    echo "checking gitee tag failed"

    exit 1    
fi

echo "gitee_tag: ${gitee_tag}"

if ! [[ "${gitee_tag}" =~ '"commit"' ]]; then
    echo "checking gitee tag failed"

    exit 1 
fi  



gitee_tag=$(echo "${gitee_tag}" | grep -oP "(?<=\")${github_latest_commit}(?=\")" | head -1)
echo "gitee_tag: ${gitee_tag}"

if [ "${gitee_tag}" = "${github_latest_commit}" ]; then
    echo "gitee tag ${gitee_tag} already synced"

    exit 0
fi
echo "begin to sync ${github_latest_commit}"


echo "cloning github repo"
git clone https://github.com/javascript-obfuscator/javascript-obfuscator-ui
cd javascript-obfuscator-ui
git checkout "${github_latest_commit}"
echo "installing deps"
npm install
npm run updatesemantic
cd ..

mkdir static-build
mkdir -p static-build/static/dist/stylesheets
mkdir -p static-build/static/images
mkdir -p static-build/static/semantic/assets/fonts
mkdir -p static-build/workers


mv javascript-obfuscator-ui/dist/index.html static-build/
mv javascript-obfuscator-ui/dist/bundle.js* static-build/static/dist/
mv javascript-obfuscator-ui/dist/stylesheets/* static-build/static/dist/stylesheets/
mv javascript-obfuscator-ui/dist/workers/* static-build/workers/
mv javascript-obfuscator-ui/public/images/* static-build/static/images/
mv javascript-obfuscator-ui/public/semantic/assets/fonts/* static-build/static/semantic/assets/fonts/

# cdn
find static-build/ -name "*.css" | xargs sed -i -e 's/fonts\.googleapis\.com/fonts\.dogedoge\.com/g'

# dist
# ├── bundle.js
# ├── bundle.js.map
# ├── index.html
# ├── stylesheets
# │   ├── bundle.css
# │   └── bundle.css.map
# └── workers
#     ├── obfuscation-worker.js
#     └── obfuscation-worker.js.map


# ├── index.html
# ├── static
# │   ├── dist
# │   │   ├── bundle.js
# │   │   ├── bundle.js.map
# │   │   └── stylesheets
# │   │       ├── bundle.css
# │   │       └── bundle.css.map
# │   ├── images
# │   │   └── logo.png
# │   └── semantic
# │       └── assets
# │           └── fonts
# │               ├── icons.eot
# │               ├── icons.svg
# │               ├── icons.ttf
# │               ├── icons.woff
# │               └── icons.woff2
# └── workers
#     ├── obfuscation-worker.js
#     └── obfuscation-worker.js.map


git config --global http.postbuffer 524288000

echo "cloning gitee repo"
git clone "https://gitee.com/${SECRETS_GITEE_USERNAME}/${GITEE_REPO}.git"
cd "${GITEE_REPO}" || exit 1

git config user.name "${SECRETS_GITEE_USERNAME}"

rm -rf static
rm -rf workers
rm ./*.html

cp -r ../static-build/* ./

# log something to enable git push everytime...
echo "${github_latest_commit} $(date "+%Y-%m-%d %H:%M:%S")" >> mylog.log

git add .
git commit -m "${github_latest_commit}"
git tag -a "${github_latest_commit}" -m "${github_latest_commit}"

echo "git push to gitee"
if ! git push --follow-tags --repo "https://${SECRETS_GITEE_USERNAME}:${SECRETS_GITEE_PASSWORD}@gitee.com/${SECRETS_GITEE_USERNAME}/${GITEE_REPO}.git"; then
    echo "git push to gitee failed"

    exit 1
fi

echo "wait 5 seconds after push"
sleep 5


echo "requesting gitee access token"
SECRETS_GITEE_ACCESS_TOKEN=$(curl --silent -X POST --data-urlencode "grant_type=password" --data-urlencode "username=${SECRETS_GITEE_USERNAME}" --data-urlencode "password=${SECRETS_GITEE_PASSWORD}" --data-urlencode "client_id=${SECRETS_GITEE_CLIENT_ID}" --data-urlencode "client_secret=${SECRETS_GITEE_CLIENT_SECRET}" --data-urlencode "scope=projects" "${SECRETS_PROXY_URL}https://gitee.com/oauth/token" |  grep -oP '(?<="access_token":")[\da-f]+(?=")')
if [ "${SECRETS_GITEE_ACCESS_TOKEN}" = "" ]; then
    echo "request gitee access token failed"

    exit 1
fi


echo "rebuilding gitee pages"
rebuild_result=$(curl --silent -X POST --header 'Content-Type: application/json;charset=UTF-8' "${SECRETS_PROXY_URL}https://gitee.com/api/v5/repos/${SECRETS_GITEE_USERNAME}/${GITEE_REPO}/pages/builds" -d "{\"access_token\":\"${SECRETS_GITEE_ACCESS_TOKEN}\"}")
if [ "$(echo "${rebuild_result}"  | grep -oP "(?<=\")queued(?=\")")" != "queued" ]; then
    echo "rebuild gitee pages failed: ${rebuild_result}"

    exit 1         
fi


# echo "git push new tag to gitee"
# git tag -a "${github_latest_commit}" -m "${github_latest_commit}"
# if ! git push --repo "https://${SECRETS_GITEE_USERNAME}:${SECRETS_GITEE_PASSWORD}@gitee.com/${SECRETS_GITEE_USERNAME}/${GITEE_REPO}.git" --tags; then
#     echo "git push new tag to gitee failed"
  
#     exit 1
# fi


# notify me
echo -e "$(date "+%Y-%m-%d %H:%M:%S")\n\
${GITHUB_REPOSITORY}\n\
${github_latest_commit} sync done." | curl --silent -X POST "${SECRETS_PUSH_URL}" --data-binary @- 
