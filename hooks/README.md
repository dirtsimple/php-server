## Docker Hub Build Rules

This directory is for controlling the build of multiple repository versions.  It contains a [build script](build) to set the needed build arguments (`PHP_VER` and `OS_VER`) to create an appropriate image, and this document, which is a [jqmd](https://github.com/bashup/jqmd) script for updating the docker hub build rules.

When you have complex build rules, the docker hub UI is incredibly inconvenient, since you cannot edit existing build rules, the full tag/sourcename rules aren't visible, etc.  So putting them in a file like this lets them be easily edited, revision-controlled, etc.

### Build Rules

For each git release tag (e.g. 2.0.0, 2.0.1, etc.), we want to build multiple PHP versions.  "Minor" versions are only accessible via an exact PHP version request, while "major" versions are also available under the major version tag variants.  So `major 7.2.26` means to tag PHP 7.2.26 under the `7.2` tag as well as under 7.2.26.   The "latest" tag is like "major", except that the version is also tagged as "latest".

```shell
build-rules() {
	image "dirtsimple/php-server"

	latest "7.1.33"
	major  "7.2.26"
	major  "7.3.13"

	#minor  "7.2.29"  # alpine 3.10
	#minor  "7.3.16"

	#version "master" "unstable" Branch b62210f7-f252-4006-b1ad-c545d08bf969
}
```

### Basic Settings

```yaml
envvars: []

autotests: 'OFF'        # 'OFF', 'SOURCE_ONLY', or 'SOURCE_AND_FORKS'
repo_links: false       # boolean true or false; true equals "enable for base image"

# ---
# Additional possible top-level settings; it's not 100% clear what some of them do, so
# use at your own risk
# ---

#build_in_farm: true
#channel: Stable

# These *might* let you switch repos, if you're linking to Github (?)
#owner: github-owner-name
#repository: github-repo-name
```

### Specific Build Rules

Each entry under `build_settings` describes a build rule.  Note that UUIDs are optional, but should not be copied from one project or rule to another.

For convenience in specifying the rules, we'll define some functions:

```shell
latest(){ major   "$1" "${2:+$2,}latest" "${@:3}"; }
major(){  minor   "$1" "${2:+$2,}${1%.*},${1%.*}-{sourceref},${1%.*}-{\\1}.x" "${@:3}"; }
minor(){  version "([0-9]+)\\.[0-9.]+" "$1-{sourceref},$1-{\\1}.x${2:+,$2}" Tag "${@:3}"; }

version() {
	local t='jqmd_data({
		build_settings: [{
			source_type: "\($kind)",
			source_name: "/^\($match)$/",
			tag: "\($build)",
			autobuild: true,
			build_context: "/",
			dockerfile: "Dockerfile",
			nocache: false,
			"uuid":"\($uuid)"
		}]
	})'
	APPLY "$t" match="$1" build="$2" kind="${3:-Tag}" uuid="${4-}"
}
```

### Implementation

Here's the code that does the actual work.  It's generic for any set of build rules, simply using the "image" property defined above to identify the image, and the `UNAME` and `UPASS` environment variables to authenticated with.

Basically, you can do this to update your settings:

~~~sh
$ export UNAME=myname UPASS=mypass
$ jqmd hooks/README.md push
~~~

Or this to fetch your existing settings (just start with only an `image:` line in the file):

~~~sh
$ jqmd hooks/README.md fetch
~~~

This will output your existing settings in JSON to use as a starting point for your version of the file.

Here's the actual runtime code:

```shell
image() { IMAGE=$1; }

hub() { curl -s "${@:2}" https://hub.docker.com"$1"; }
json() { "$@" -H "Content-Type: application/json" -d @-; }
post() { "$@" -X POST; }
patch() { "$@" -X PATCH; }
raw() { "${@:2}" | jq -r "$1"; }
auth() { login; "$@" -H "Authorization: JWT ${TOKEN}"; }
config() { find-image; hub "$SOURCE" "$@"; }

login() {
	# Expect UNAME AND UPASS to be supplied as env vars, and fetch token
	[[ $TOKEN ]] ||	TOKEN=$(
		jq -n '{username:env.UNAME,password:env.UPASS}' | raw .token json post hub /v2/users/login/
	)
}

find-image() {
	[[ $SOURCE ]] || SOURCE=$(raw .objects[].resource_uri hub "/api/build/v1/source/?image=$IMAGE")
}

[[ $UNAME && $UPASS ]] || {
	echo "UNAME and UPASS must be set to your docker hub credentials (e.g. via export UNAME=...)"
	exit 64
} >&2

JQ_OPTS -n  # generating, not filtering
build-rules

[[ $IMAGE ]]  || {
	echo '`image` must be defined in build-rules' >&2; exit 64
}

case ${1-} in
	push) RUN_JQ . | patch json auth config | jq . ;;
	dump) RUN_JQ . ;;  # dump current settings as JSON
	fetch)
		# fetch existing settings and dump them to the console
		login; find-image; CLEAR_FILTERS; JQ_OPTS -n; JSON "$(auth config)"
		builds=$(RUN_JQ -r .build_settings[])

		# Remove build_settings and things you can't change via PATCH
		FILTER 'del(.build_settings, .deploykey, .image, .provider, .resource_uri, .state, .uuid)'
		for setting in $builds; do
			JSON '{build_settings:[('"
				$(auth hub "$setting")
			"' | {source_type,source_name,tag,autobuild,nocache,build_context,dockerfile,uuid} )]}'
		done
		RUN_JQ .
		;;
	local)
		multibuild() { DOCKER_TAG=$2-$3.$4,$2-$3.x,$1-$3.x,$2,$1 hooks/build; }
		for ver in "${@:2}"; do
			min=${ver%-*}; maj=${min%.*}; rel=${ver#*-}; rmin=${rel#*.}; rmaj=${rel%%.*}
			multibuild "$maj" "$min" "$rmaj" "$rmin"
		done
		;;
	*) echo "argument required: local, fetch, dump, or push" >&2; exit 64 ;;
esac

CLEAR_FILTERS
```

