#!/usr/bin/env sh

set -e

DEFAULT_RAVEN_URL="http://127.0.0.1:7080"

WRK_THREADS=${WRK_THREADS:-8}
WRK_CONNECTIONS=${WRK_CONNECTIONS:-24}
WRK_DURATION=${WRK_DURATION:-60s}

RAVEN_URL=${RAVEN_URL:-$DEFAULT_RAVEN_URL}

usage() {
    echo "Usage: $0 (init|start|nuke|bench)"
}

init () {
    # create a volume
    docker volume create --name postgres-chinook

    # initialise postgres
    docker run --rm -v postgres-chinook:/var/lib/postgresql/data -e POSTGRES_USER=admin -e POSTGRES_DB=chinook hasuraci/postgres-init:d7cf835

    # start postgres
    docker run --name postgres-chinook -d -v postgres-chinook:/var/lib/postgresql/data -p 7432:5432 -e POSTGRES_USER=admin hasuraci/postgres-server:d7cf835

    # wait for postgres to come up
    sleep 5

    # Get chinook database
    # wget -O chinook.sql -c 'https://github.com/xivSolutions/ChinookDb_Pg_Modified/raw/pg_names/chinook_pg_serial_pk_proper_naming.sql'

    # copy it into the container
    docker cp chinook.data postgres-chinook:/chinook.data
    # import the data
    docker exec postgres-chinook pg_restore -h 127.0.0.1 -p 5432 -U admin -d chinook /chinook.data

    # initialise raven
    docker run --rm hasuraci/raven:de42ddb raven --host 172.17.0.1 -p 7432 -u admin -p '' -d chinook initialise

    # start raven
    docker run --name raven-chinook -p 7080:8080 -d hasuraci/raven:de42ddb raven --host 172.17.0.1 -p 7432 -u admin -p '' -d chinook serve --connections 100

    # wait for raven to come up
    sleep 5

    # add raven metadata
    yaml2json metadata.yaml | curl -d @- -XPOST -H 'X-Hasura-User-Id:0' -H 'X-Hasura-Role:admin' $RAVEN_URL/v1/query
}

start () {
    # start postgres
    docker start postgres-chinook
    # wait for postgres to come up
    sleep 5
    # start raven
    docker start raven-chinook
}

stop () {
    echo 'stopping raven-chinook container'
    docker stop raven-chinook
    echo 'stopping postgres-chinook container'
    docker stop postgres-chinook
}

nuke () {
    echo 'removing raven-chinook container'
    docker stop raven-chinook && docker rm raven-chinook
    echo 'removing postgres-chinook container'
    docker stop postgres-chinook && docker rm postgres-chinook
    echo 'removing postgres-chinook volume'
    docker volume rm postgres-chinook
}

bench_query ()
{
    echo "running benchmark: $1"
    set +e
    # here the custom json output is written to the stderr
    # this is because wrk doesn't allow you to suppress the default output
    wrk -c $WRK_CONNECTIONS -d $WRK_DURATION -t $WRK_THREADS -s bench.lua --timeout 300s "$RAVEN_URL" $1 2> stats/$1.json
    # this is needed because wrk's error is written to stderr
    rc=$?; if [ $rc -ne 0 ]; then cat stats/$1.json; set -e; exit $rc; fi
}

bench () {
    echo 'starting benchmarks'
    mkdir -p stats
    bench_query albums_tracks_genre_some
    bench_query albums_tracks_genre_all
    bench_query tracks_media_some
    bench_query tracks_media_all
}

if [ "$#" -ne 1 ]; then
    usage
    exit 1
fi

case $1 in
    init)
        init
        exit
        ;;
    start)
        start
        exit
        ;;
    stop)
        stop
        exit
        ;;
    nuke)
        nuke
        exit
        ;;
    bench)
        bench
        exit
        ;;
    *)
        echo "unexpected option: $1"
        usage
        exit 1
        ;;
esac
