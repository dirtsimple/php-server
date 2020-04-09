## Docker Hub Build Rules

This directory is for controlling the build of multiple repository versions.  It contains a [build script](build) to set the needed build arguments (`PHP_VER` and `OS_VER`) to create an appropriate image, and this document, which is a [jqmd](https://github.com/bashup/jqmd) script for updating the docker hub build rules.

When you have complex build rules, the docker hub UI is incredibly inconvenient, since you cannot edit existing build rules, the full tag/sourcename rules aren't visible, etc.  So putting them in a file like this lets them be easily edited, revision-controlled, etc.

This script is not project-specific; you can target any image by changing the `image:` line to target your project, and running `fetch` to get your initial settings, and then editing the file to match them.  (See under [Implementation](#implementation), below.)

### Basic Settings

```yaml
image: dirtsimple/php-server  # image name: this is the only required setting
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

For convenience in specifying the rules, we'll define some variables first:

```shell
# Pattern matches
dot='[.]'
num='[0-9]+'
tail="$dot[0-9.]+"
release="($num)$tail"
export match="($tail)?-$release"

# Tag interpolation
export major='{\1}'
export minor='{\1}{\2}'
export majorx="$major-{\3}.x"
export minorx="$minor-{\3}.x"
export all="{sourceref},$major,$minor,$majorx,$minorx"
```



```yaml
build_settings:

  # Treat 7.1 tags as 'latest'
  - source_type:   Tag
    source_name:   "/^(7.1)\\(env.match)$/"
    tag:           "\\(env.all),latest"
    build_context: /
    dockerfile:    Dockerfile
    autobuild:     true
    nocache:       false
    uuid:          e023fa4f-1a9d-48ba-bb96-65a999709273

  # Build 7.2+ according to pattern
  - source_type:   Tag
    source_name:   "/^(7.[2-4])\\(env.match)$/"
    tag:           "\\(env.all)"
    build_context: /
    dockerfile:    Dockerfile
    autobuild:     true
    nocache:       false
    uuid:          4a4f8d0c-a522-4dc8-a7b4-ce5f876f39b6

  # master is unstable
  - source_type:   Branch
    source_name:   "master"
    tag:           "unstable"
    autobuild:     true
    nocache:       false
    build_context: /
    dockerfile:    Dockerfile
    uuid:          b62210f7-f252-4006-b1ad-c545d08bf969

```

Legacy builds (not included in push):

~~~yaml
build_settings:
  # Fixed version from master
  - source_type: Branch
    source_name: "master"
    tag:         "latest"
    dockerfile:  /
    autobuild:   false
    nocache:     true
    uuid:        3361111d-cbc9-4265-b626-861ffd552df0

  # Any tag - disabled
  - source_type: Tag
    source_name: "/.*/"
    tag:         "{sourceref}"
    autobuild:   false
    nocache:     true
    dockerfile:  /
    uuid:        e958e00e-88c1-41e2-ac37-2cab6a75ee33
~~~

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
	[[ $IMAGE ]]  || IMAGE=$(RUN_JQ -r .image)
	[[ $SOURCE ]] || SOURCE=$(raw .objects[].resource_uri hub "/api/build/v1/source/?image=$IMAGE")
}

[[ $UNAME && $UPASS ]] || {
	echo "UNAME and UPASS must be set to your docker hub credentials (e.g. via export UNAME=...)"
	exit 64
} >&2

JQ_OPTS -n  # generating, not filtering

case ${1-} in
	push) RUN_JQ 'del(.image)' | patch json auth config | jq . ;;
	dump) RUN_JQ . ;;  # dump current settings as JSON
	fetch)
		# fetch existing settings and dump them to the console
		login; find-image; CLEAR_FILTERS; JQ_OPTS -n; JSON "$(auth config)"
		builds=$(RUN_JQ -r .build_settings[])

		# Remove build_settings and things you can't change via PATCH
		FILTER 'del(.build_settings, .deploykey, .provider, .resource_uri, .state, .uuid)'
		for setting in $builds; do
			JSON '{build_settings:[('"
				$(auth hub "$setting")
			"' | {source_type,source_name,tag,autobuild,nocache,build_context,dockerfile,uuid} )]}'
		done
		RUN_JQ .
		;;
	*) echo "argument required: fetch, dump, or push" >&2; exit 64 ;;
esac

CLEAR_FILTERS
```

