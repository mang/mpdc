#!/usr/bin/env ruby

# MPDC - Music Player Daemon Cabinet

# This is a simple glue between MusicCabinet (http://dilerium.se/musiccabinet/)
# and Music Player Daemon (http://mpd.wikia.com/wiki/Music_Player_Daemon_Wiki). It
# allows you to create playlists based on meta data (such as related artists, top
# track, genre tags) from Last.fm.


# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

require 'optparse'
require 'parseconfig'
require 'pg'
require 'librmpd'
require 'mpdserver'

class PlaylistCreator

  def initialize()
    @default_values={
      :track_selection => 'toptracks',
      :playlist_position => 'replace',
      :shuffle => false,
      :track_limit => 25,
      :related_artists_limit => 5,
      :config_file => File.expand_path('~/.mpdcrc'),
      :mpd_host => 'localhost',
      :mpd_port => 6600,
      :mpd_password => '',
      :db_user => 'postgres',
      :db_password => '',
      :db_host => 'localhost',
      :db_port => 5432,
      :db_name => 'musiccabinet',
      :dryrun => false,
      :verbose => false,
      :help => false
    }
  end

  def parse_config()
    if File.exist?(@default_values[:config_file])
      config_file=@default_values[:config_file]
      if @default_values[:verbose]
        print "Loading config file \"%s\"..." %[@default_values[:config_file]]
      end
      config=ParseConfig.new(config_file)
      for conf_key in config.get_params do
        @default_values[conf_key.to_sym]=config[conf_key]
      end
      if @default_values[:verbose]
        puts " done"
      end
    end
  end

  def parse_options()

    options=@default_values
    OptionParser.new do|opts|
      opts.banner = 'Usage: %s [options] [-a <artist_regexp>|-g <genre_regexp>]' % [$0]

      opts.on('-a','--artist <regexp>','base playlist creation on regular expression for artist') do|artist|
        options[:artist]=artist
      end
      opts.on('-t','--top-tracks','select top ranked tracks for artist (only with -a) (default for -a)') do
        options[:track_selection]='toptracks'
      end
      opts.on('-r','--related','select tracks from artist related to artist (only with -a) (implies -s)') do
        options[:track_selection]='related'
        options[:shuffle]=true
      end
      opts.on('-g','--genres <regexp>','base playlist creation on genre tags described by <regexp> (implies -s)') do|genre_regexp|
        options[:track_selection]='genres'
        options[:shuffle]=true
        options[:genre_regexp]=genre_regexp
      end
      opts.on('-G','--list-genres <regexp>','search for represented genres tags') do|genre_regexp|
        options[:track_selection]='list_genres'
        options[:genre_regexp]=genre_regexp
      end
      opts.on('-e','--end','insert tracks at end of playlist (default:replace current playlist)') do
        options[:playlist_position]='end'
      end
      opts.on('-s','--shuffle','shuffle mpd playlist after insertation') do
        options[:shuffle_mpd]=true
      end
      opts.on('-l','--track-limit <N>','set the track limit to <N> (default:25)') do|track_limit|
        options[:track_limit]=track_limit
      end
      opts.on('-L','--artists-limit <N>','set the track limit per artist to <N> (not for -t) (default:5)') do|related_artists_limit|
        options[:related_artists_limit]=related_artists_limit
      end
      opts.on('-d','--dry','just print tracks, don\'t actually add/play them') do
        options[:dryrun]=true
      end
      opts.on('--music-dir <dir>','set the MPD local music directory to <dir>') do|music_dir|
        options[:music_dir]=music_dir
      end
      opts.on('--mpd-host <host>','set the MPD host to <host> (default:localhost)') do|mpd_host|
        options[:mpd_host]=mpd_host
      end
      opts.on('--mpd-port <port>','set the MPD port to <port> (default:6600)') do|mpd_port|
        options[:mpd_port]=mpd_port
      end
      opts.on('--mpd-password <pswd>','set the MPD password to <pswd>') do|mpd_password|
        options[:mpd_password]=mpd_password
      end
      opts.on('--db-host <host>','set the database host to <host> (default:localhost)') do|db_host|
        options[:db_host]=db_host
      end
      opts.on('--db-name <name>','set the database name to <name> (default:musiccabinet)') do|db_name|
        options[:db_name]=db_name
      end
      opts.on('--db-port <port>','set the database port to <port> (default:5432)') do|db_port|
        options[:db_port]=db_port
      end
      opts.on('-u','--db-user <user>','set the database user to <user> (default:postgres)') do|db_user|
        options[:db_user]=db_user
      end
      opts.on('-p','--db-password <pswd>','set the database pswd to <pswd>') do|db_pswd|
        options[:db_pswd]=db_pswd
      end
      opts.on('-v','--verbose','be more verbose') do
        options[:verbose]=true
      end
      opts.on('-V','--version','print version') do
        puts "MPDC version 0.1"
      end
      opts.on('-h','--help','display this help screen') do
        puts opts
        exit
      end
    end.parse!

    unless options[:music_dir][-1.1]=='/'
      options[:music_dir]=options[:music_dir]+'/'
      puts "==! Warning: \"music_dir\" should end with '/'"
    end

    @options=options
  end 

  def pg_connect()
    if @options[:db_password].empty?
      puts "No database password supplied"
    else
      @pg_connection=PG::Connection.new(:host => @options[:db_host],
                                        :port => @options[:db_port],
                                        :dbname => @options[:db_name],
                                        :user => @options[:db_user],
                                        :password => @options[:db_password]);
    end
  end

  def get_option(option)
    @options[option.to_sym]
  end

  def set_option(option,value)
    @options[option.to_sym]=value
  end

  def get_artist()
    pg_result=@pg_connection.exec('SELECT ma.artist_name_capitalization,ma.id '+
                                  'FROM music.artist ma '+
                                  'INNER JOIN library.artist la ON ma.id=la.artist_id '+
                                  'WHERE artist_name ~ upper($1)',
                                  [@options[:artist]])
    rows=pg_result.count
    if rows>50
      abort("Too many matches, please be more specific")
    elsif rows>1
      count=0
      while count<rows do
        puts "[%s] %s" % [count,pg_result[count]['artist_name_capitalization']]
        count=count+1
      end
      if @options[:track_selection] == 'toptracks'
        choice="[0-"+(rows-1).to_s+"|nil=all]"
      else
        choice="[0-"+(rows-1).to_s+"]"
      end
      print "There %s matches for \"%s\", please choose a number %s: " % [rows,@options[:artist],choice]
      num=STDIN.gets.chop
      if num.empty?
        if @options[:track_selection] == 'toptracks'
          artist={
            :ids=>pg_result.field_values('id').map{|x| "#{x}"}.join(','),
            :names=>pg_result.field_values('artist_name_capitalization').map{|x| "'#{x}'"}.join(', ')
          }
        else
          abort('you must choose ONE number')
        end
      else
        num=Integer(num)
        artist={
          :ids=>pg_result[num]['id'],
          :names=>pg_result[num]['artist_name_capitalization']
        }
      end
    elsif rows>0
      artist={
        :ids=>pg_result[0]['id'],
        :names=>pg_result[0]['artist_name_capitalization']
      }
    else
      abort_msg='No match for artist regexp "/%s/"' %
        [@options[:artist]]
      abort(abort_msg)
    end
    artist
  end

  def get_top_tracks(artist_id)
    @pg_connection.exec('SELECT ma.artist_name_capitalization, '+
                        '       al.album_name_capitalization, '+
                        '       mt.track_name_capitalization, '+
                        '       d.path, '+
                        '       f.filename '+
                        'FROM library.artisttoptrackplaycount att '+
                        'INNER JOIN library.track lt ON lt.id = att.track_id '+
                        'INNER JOIN music.track mt ON mt.id = lt.track_id '+
                        'INNER JOIN music.artist ma ON ma.id = mt.artist_id '+
                        'INNER JOIN music.album al ON lt.album_id = al.id '+
                        'INNER JOIN library.file f ON lt.file_id = f.id '+
                        'INNER JOIN library.directory d ON f.directory_id  = d.id '+
                        'WHERE att.artist_id = any($1) '+
                        'ORDER BY rank ASC LIMIT $2',
                        ["{"+artist_id+"}",
                         @options[:track_limit]])
  end

  def get_related_tracks(artist_id)
    @pg_connection.exec('SELECT ma.artist_name_capitalization, '+
                        '       al.album_name_capitalization, '+
                        '       mt.track_name_capitalization, '+
                        '       d.path, '+
                        '       f.filename '+
                        'FROM (SELECT att.track_id, att.artist_id, ar.weight AS artist_weight, RANK() '+
                        'OVER (PARTITION BY att.artist_id '+
                        'ORDER BY (RANDOM()*(110-RANK+(play_count/3))) DESC) AS artist_rank '+
                        'FROM library.artisttoptrackplaycount att '+
                        'INNER JOIN (SELECT source_id, target_id, weight '+
                        'FROM music.artistrelation '+
                        'UNION ALL select $1, $1, 1) ar '+
                        'ON ar.target_id = att.artist_id AND ar.source_id = $1) '+
                        'ranked_tracks '+
                        'INNER JOIN library.track lt ON ranked_tracks.track_id = lt.id '+
                        'INNER JOIN library.file f ON lt.file_id = f.id '+
                        'INNER JOIN library.directory d ON f.directory_id = d.id '+
                        'INNER JOIN music.track mt ON mt.id = lt.track_id '+
                        'INNER JOIN music.artist ma ON ma.id = mt.artist_id '+
                        'INNER JOIN music.album al ON lt.album_id = al.id '+
                        'WHERE ranked_tracks.artist_rank <= $2 '+
                        'ORDER BY RANDOM() * ranked_tracks.artist_weight * '+
                        'ranked_tracks.artist_weight DESC LIMIT $3;',
                        [artist_id,
                         @options[:related_artists_limit],
                         @options[:track_limit]])
  end

  def get_genre_tracks(genres)
    genres=genres.map{|x| "'#{x[0]}'"}.join(',')
    @pg_connection.prepare('pg-prepared',
                           'SELECT ma.artist_name_capitalization, '+
                           '       al.album_name_capitalization, '+
                           '       mt.track_name_capitalization, '+
                           '       d.path, '+
                           '       f.filename '+
                           'FROM (SELECT att.track_id, att.artist_id, tag.tag_count AS tag_weight, RANK() '+
                           'OVER (PARTITION BY att.artist_id '+
                           'ORDER BY (RANDOM()*(110-RANK+(play_count/3))) DESC) AS artist_rank '+
                           'FROM library.artisttoptrackplaycount att '+
                           'INNER JOIN (select toptag.artist_id, sum(tag_count) AS tag_count '+
                           'FROM music.artisttoptag toptag '+
                           'INNER JOIN music.tag tag ON toptag.tag_id = tag.id '+
                           'WHERE tag.tag_name IN ('+genres+') '+
                           'GROUP BY toptag.artist_id) tag ON tag.artist_id = att.artist_id) '+
                           'ranked_tracks '+
                           'INNER JOIN library.track lt ON ranked_tracks.track_id = lt.id '+
                           'INNER JOIN library.file f ON lt.file_id = f.id '+
                           'INNER JOIN library.directory d ON f.directory_id = d.id '+
                           'INNER JOIN music.track mt ON mt.id = lt.track_id '+
                           'INNER JOIN music.artist ma ON ma.id = mt.artist_id '+
                           'INNER JOIN music.album al ON lt.album_id = al.id '+
                           'WHERE ranked_tracks.artist_rank <= $1 '+
                           'ORDER BY (RANDOM()/8) * ranked_tracks.tag_weight '+
                           'DESC LIMIT $2;')
    @pg_connection.exec_prepared('pg-prepared',
                                 [@options[:related_artists_limit],
                                  @options[:track_limit]])
  end

  def get_genre_list(genre_regexp)
    @pg_connection.exec('SELECT tag_name '+
                        'FROM music.tag '+
                        'WHERE tag_name ~ $1;',
                        [genre_regexp])
  end

  def inspect()
    @options
  end

end

if __FILE__ == $0

  trap("INT") do
    puts "\ngot INT signal, quitting"
    Kernel.exit(0)
  end

  creator=PlaylistCreator.new()
  creator.parse_config
  creator.parse_options
  creator.pg_connect

  # get track list from db
  case creator.get_option('track_selection')
  when 'toptracks'
    artist=creator.get_artist()
    plural = "s" if artist.count>1
    puts "==> Selecting top %s tracks for artist%s %s" %
      [creator.get_option('track_limit'),
       plural,
       artist[:names]]
    pg_result=creator.get_top_tracks(artist[:ids])
  when 'related'
    artist=creator.get_artist()
    puts "==> Selecting %s tracks from artists related to %s" %
      [creator.get_option('track_limit'),
       artist[:names]]
    pg_result=creator.get_related_tracks(artist[:ids])
  when 'genres'
    pg_result=creator.get_genre_list(creator.get_option('genre_regexp'))
    if pg_result.count==0
      abort_msg='No match for genre tag regexp "/%s/"' %
        [creator.get_option('genre_regexp')]
      abort(abort_msg)
    end      
    genres=pg_result.values()
    puts "==> Selecting %s tracks with genre tags %s" %
      [creator.get_option('track_limit'),
       pg_result.map{|x| "\"#{x['tag_name']}\""}.join(', ')]
    pg_result=creator.get_genre_tracks(genres)
  when 'list_genres'
    pg_result=creator.get_genre_list(creator.get_option('genre_regexp'))
    puts pg_result.values()
    exit
  end

  # prepare db result
  file_list=pg_result.to_a
  if creator.get_option('shuffle')
    file_list=file_list.shuffle
  end

  # iterate on track list
  rows=pg_result.count
  count=0

  # connect to mpd
  unless creator.get_option('dryrun')
    mpd = MPD.new(creator.get_option('mpd_host'),
                  creator.get_option('mpd_port'))
    mpd.connect()
    if creator.get_option('mpd_password').length>0
      mpd.password(creator.get_option('mpd_password'))
    end

    # pre track list iteration
    if creator.get_option('playlist_position')=='replace'
      mpd.clear()
    end
  end

  while count<rows do
    track="%s - %s (%s)" % [file_list[count]['artist_name_capitalization'],
                            file_list[count]['track_name_capitalization'],
                            file_list[count]['album_name_capitalization']]
    file="%s/%s" % [file_list[count]['path'].gsub(creator.get_option('music_dir'),''),
                    file_list[count]['filename']]
    # give playlist to mpd
    if creator.get_option('dryrun')
      puts track
    else
      puts "added \"%s\"" % [track]
      mpd.add(file)
      mpd.play if count==0
    end
    count=count+1
  end

  # post track list iteration
  if creator.get_option('shuffle_mpd')
    mpd.shuffle()
  end
  unless creator.get_option('dryrun')
    mpd.disconnect()
  end
  pg_result.clear()

end

exit
