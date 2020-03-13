#!/bin/bash

set -e

apt-get update
apt-get install -y jq

this_commit=$(echo $BUILDKITE_COMMIT | tr -d '"')
tags=$(curl https://api.github.com/repos/uber/baseweb/git/refs/tags?access_token=${GITHUB_AUTH_TOKEN})
latest_tagged_commit=$(echo $tags | jq '.[-1].object.sha' | tr -d '"')

echo this commit: $this_commit
echo latest tagged commit: $latest_tagged_commit

# deploy to netlify the master
if [ "$BUILDKITE_BRANCH" = "master" ]; then
  # we build the doc site on purpose here - it will slow down builds on the master only
  FORCE_EXTRACT_REACT_TYPES=true yarn documentation:build
  yarn netlify deploy --dir=public --prod
fi

#BUILDKITE_MESSAGE="Release v8.4.0 (#1532)"
if [ "$this_commit" = "$latest_tagged_commit" ]; then
  echo current commit matches latest tagged commit
  echo deploying to now
  version=$(echo $BUILDKITE_MESSAGE | cut -d' ' -f 2)
  echo version $version

  # deploy to now the versioned docs site
  now --scope=uber-ui-platform --token=$ZEIT_NOW_TOKEN --public --no-clipboard deploy ./public > deployment.txt
  deployment=`cat deployment.txt`
  cname="${version//./-}"
  curl -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
     -H "Authorization: Bearer $CF_API_KEY" \
     -H "Content-Type: application/json" \
     --data "{\"type\":\"CNAME\",\"name\":\"$cname.baseweb.design\",\"content\":\"alias.zeit.co\",\"ttl\":1,\"priority\":10,\"proxied\":false}"
  now --scope=uber-ui-platform --token=$ZEIT_NOW_TOKEN alias $deployment "$cname.baseweb.design"
else
  echo current commit does not match latest tagged commit
  echo exited without deploying to now
fi
