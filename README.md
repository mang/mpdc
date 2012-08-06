MPDC - MusicPlayerDaemonCabinet
===============================

MPDC is a client that integrates the database of [MusicCabinet](http://dilerium.se/musiccabinet/) with [MusicPlayerDaemon](http://mpd.wikia.com/wiki/Music_Player_Daemon_Wiki)

MusicCabinet is built as an add-on to Subsonic music streaming server. Though MPDC
does not require Subsonic to be running, MusicCabinet does in order to (at least
in an convenient way) create and update the database. Therefore MPDC is not much
usefull without running Subsonic. What does it do?

What does it do?
----------------
MPDC implements some of the featueres of MusicCabinet into MPD by providing a
simple cli client that lets the user searches for artists or genre tags to create
playlist based on. The behaviour can be modified to select

* Top ranked tracks for an given artist
* Tracks from artists related to a given artist
* Tracks from artists described by given genre tags

The user may also specify how many tracks, how many tracks per artist mpdc should
return, as well as where in the mpd playlist the tracks should be inserted Usage

Usage
-----
MPDC needs something to search for, either a regexp for an artist (-a) or regexp for genre tags (-g) . For example,

    mpdc.rb ~/src/mpdc/mpdc.rb -l 15 -g '^(riot grrrl|punk)$' -e

adds 15 tracks of punk and riot grrrl music to the end of the current mpd playlist

Full list of options:

    Usage: /home/mang/src/mpdc/git/mpdc.rb [options] [-a <artist_regexp>|-g <genre_regexp>]
        -a, --artist <regexp>            base playlist creation on regular expression for artist
        -t, --top-tracks                 select top ranked tracks for artist (only with -a) (default for -a)
        -r, --related                    select tracks from artist related to artist (only with -a) (implies -s)
        -g, --genres <regexp>            base playlist creation on genre tags described by <regexp> (implies -s)
        -G, --list-genres <regexp>       search for represented genres tags
        -e, --end                        insert tracks at end of playlist (default:replace current playlist)
        -s, --shuffle                    shuffle mpd playlist after insertation
        -l, --track-limit <N>            set the track limit to <N> (default:25)
        -L, --artists-limit <N>          set the track limit per artist to <N> (not for -t) (default:5)
        -d, --dry                        just print tracks, don't actually add/play them
            --music-dir <dir>            set the MPD local music directory to <dir>
            --mpd-host <host>            set the MPD host to <host> (default:localhost)
            --mpd-port <port>            set the MPD port to <port> (default:6600)
            --mpd-password <pswd>        set the MPD password to <pswd>
            --db-host <host>             set the database host to <host> (default:localhost)
            --db-name <name>             set the database name to <name> (default:musiccabinet)
            --db-port <port>             set the database port to <port> (default:5432)
        -u, --db-user <user>             set the database user to <user> (default:postgres)
        -p, --db-password <pswd>         set the database pswd to <pswd>
        -v, --verbose                    be more verbose
        -V, --version                    print version
        -h, --help                       display this help screen

If present, the client also reads the file ~/.mpdcrc for configuration. The file should be in standard unix config format, as key="value". Accepted keys and values are

    track_selection       = toptracks|related|genres|list_genres
    playlist_position     = replace|end
    shuffle               = true
    track_limit           = <number>
    related_artists_limit = <number>
    mpd_host
    mpd_port
    mpd_password
    db_user
    db_password
    db_host
    db_port
    db_name
    dryrun                = true
    verbose               = true
    music_dir
