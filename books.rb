#!/usr/bin/env ruby
require 'csv'
require 'gli'
require 'google/api_client'
require 'google_drive'
require 'active_support'  # dependency not pulled in correctly in openlibrary
require 'openlibrary'
require 'yaml'

CONFIG = './config.yml'
TOKEN_CACHE = './token.cache'

def bail(msg, code=1)
  puts msg
  exit code
end

def open_worksheet(config)
  # google doc login with app password
  begin
    access_token = get_google_access_token(config[:oauth])
    session = GoogleDrive.login_with_oauth(access_token)
  rescue Exception => e
    bail 'login failed'
    puts e.message
  end

  # grab correct spreadsheet and worksheet
  spreadsheet = session.spreadsheet_by_title(config[:spreadsheet_name])
  bail 'cannot find spreadsheet %s' % config[:spreadsheet_name] if spreadsheet.nil?
  worksheet = spreadsheet.worksheet_by_title(config[:worksheet_name])
  bail 'cannot find worksheet %s' % config[:worksheet_name] if worksheet.nil?

  worksheet
end

def fix_name(name)
  # Fix Author name: FOO, Bar -> Foo, Bar
  # Return name if the source doesn't match
  m = name.match(/^([A-Z]+), +(.+)/)
  return name if m.nil?
  '%s, %s' % [ m[1].capitalize, m[2] ]
end

# bulk fix of names, very narrow mapping of known wonky source names
def fix_names(w)
  row = 2
  changed = 0
  until (name = w[row, 2]).empty?
    fixed = fix_name(name)
    if fixed != name
      puts '%-3s: %s\n     %s' % [row, name, fixed]
      w[row, 2] = fixed
      changed += 1
    end
    row += 1
  end
  puts 'changed %s' % changed
end

# use OpenLibrary search to fill in missing ISBNs, this does not always work, don't try to change existing ISBNs
def find_isbns(w)
  client = Openlibrary::Client.new
  found = 0
  missing = 0
  row = 2
  until (name = w[row, 2]).empty?
    isbn = w[row, 10]
    if isbn.empty?
      missing += 1
      last_name = name.split(',').first
      # search api breaks on punctuation, remove it, keep spaces
      title = w[row, 1].gsub(/([^\w ])/, '')
      begin
        results = client.search({author: last_name, title: title})
        # some results do not have an isbn, so keep trying
        for r in results
          unless r.isbn.nil?
            isbn = r.isbn.first
            break
          end
        end
        puts '%-3s: %s | %s -> %s' % [row, last_name, title, isbn]
        found += 1 unless isbn.empty?
        w[row, 10] = isbn.to_s
      rescue Exception => e
        puts '%-3s: %s' % [row, e.message]
      end
    end
    row += 1
  end
  puts 'found %s, missing %s' % [found, missing]
end

# goodreads format is (expects dates as %Y-%m-%d ISO 8601)
# Title, Author, ISBN, My Rating, Average Rating, Publisher, Binding, Year Published,
# Original Publication Year, Date Read, Date Added, Bookshelves, My Review
# my format is (dates are %Y-%m-%d)
# Title, Author, DateStart, DateFinish, Note, Days Open, Good book, Liked it, Ebook, ISBN
def export_for_goodreads(w, config, count=0)
  missing = DATA.readlines.map(&:chomp).map{|e| e.gsub(/\W/, '')}
  row = 2
  CSV.open(config[:csv_file_out], 'wb') do |csv|
    csv << ['Title', 'Author', 'ISBN', 'My Rating', 'Average Rating', 'Publisher', 'Binding', 'Year Published',
            'Original Publication Year', 'Date Read', 'Date Added', 'Bookshelves', 'My Review']
    until w[row, 1].empty? or (count > 0 and row - 1 > count) # end of sheet or just the first count records
      isbn = w[row, 10]
      # use optional whitelist in the DATA area below
      if not isbn.empty? and (missing.length == 0 or missing.include?(isbn))
        title = w[row, 1]
        # last name only
        author = w[row, 2].split(',').first
        rating = w[row, 8].count('*')
        date_read = w[row, 3]
        begin
          # GDoc date format reads out %m/%d/%Y no matter what display format you've set
          date_fmt = Date.strptime(date_read, '%m/%d/%Y').strftime('%F')
        rescue Exception => e
          puts 'row %s: %s' % [row, date_read]
          raise e
        end
        csv << [ title, author, isbn, rating, '', '', '', '', '', date_fmt, '', '', '']
        puts '%-3s: %-15s | %-10s | %s | %-13s | %s -> %s' % [row - 1, title[0..14], author[0..9], rating, isbn[0..12],
                                                              date_read, date_fmt]
      end
      row += 1
    end
  end
end

def dump_stats(w)
  row = 2
  isbns = Hash.new(0)
  until w[row, 1].empty?
    isbn = w[row, 10]
    isbns[ isbn ] += 1
    print 'row %s | %s' % [row, isbn] unless (isbn.empty? or isbn.length == 10 or isbn.length == 13)
    row += 1
  end
  puts 'total records %s, unique records %s' % [row-1, isbns.length]
end

# goodreads import seems to have ignored some books, use the export from there to find which ones
def find_missing_from_goodreads(w, config)
  row = 2
  books = {}
  # build a hash of my books keyed by isbn
  until w[row, 1].empty?
    isbn = w[row,10].to_s
    unless isbn.empty?
      books[ isbn ] = { title: w[row,1], author: w[row,2] }
    end
    row += 1
  end
  puts 'master list books includes %s unique' % books.length
  #
  # scan isbn (both 10 and 13) in export and remove those from my list
  # goodreads exported file has these headers
  # Book Id,Title,Author,Author l-f,Additional Authors,ISBN,ISBN13,My Rating,Average Rating,Publisher,Binding,
  # Number of Pages,Year Published,Original Publication Year,Date Read,Date Added, # Bookshelves,
  # Bookshelves with positions,Exclusive Shelf,My Review,Spoiler,Private Notes,Read Count,Recommended For,
  # Recommended By,Owned Copies,Original Purchase Date,Original Purchase Location,Condition,Condition Description,BCID
  # the ISBN fields look like
  # ="0374519994",="9780374519995" (or ="") which is broken and blows up the CSV parser, so strip those first
  open(config[:csv_file_in], 'r').each do |l|
    l = l.gsub(/=""/, '""').gsub(/="([\dxX]+)"/, '"\1"')
    CSV.parse(l) do |r|
      #title = r[1]
      #author = r[2]
      isbn10 = r[5].gsub(/\W/, '').to_s
      isbn13 = r[6].gsub(/\W/, '').to_s
      books.delete(isbn10)
      books.delete(isbn13)
      #found = ( books.include?(isbn10) or books.include?(isbn13) )
      #puts "%-20s | %-15s | %s | %s" % [title, author, isbn10, isbn13]
    end
  end
  puts 'after removing matches from goodreads there are %s unique' % books.length
  #books.each { |k, v| puts "%-20s | %-15s | %s " % [v[:title][0..19], v[:author][0..14], k] }
  books.each { |k, _| puts k }
end

# authorizes with oauth and gets an access token
# cf. http://www.rubydoc.info/github/gimite/google-drive-ruby/GoogleDrive.login_with_oauth
def get_google_access_token(oauth)
  client = Google::APIClient.new(application_name: oauth[:app_name], application_version: oauth[:app_version])
  auth = client.authorization
  auth.client_id = oauth[:client_id]
  auth.client_secret = oauth[:client_secret]
  auth.scope = 'https://www.googleapis.com/auth/drive https://spreadsheets.google.com/feeds/'
  auth.redirect_uri = 'urn:ietf:wg:oauth:2.0:oob'
  if File.exist? TOKEN_CACHE
    auth.refresh_token = YAML.load(File.read(TOKEN_CACHE))
  else
    print("1. Open this page:\n%s\n\n" % auth.authorization_uri)
    print('2. Enter the authorization code shown: ')
    open_browser(auth.authorization_uri)
    auth.code = $stdin.gets.chomp
  end
  auth.fetch_access_token!
  File.open(TOKEN_CACHE, 'w') {|f| f.write(YAML.dump(auth.refresh_token)) }
  auth.access_token
end

def open_browser(url)
  if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
    system "start #{url}"
  elsif RbConfig::CONFIG['host_os'] =~ /darwin/
    system "open '#{url}'"
  elsif RbConfig::CONFIG['host_os'] =~ /linux|bsd/
    system "xdg-open '#{url}'"
  end
end

#require 'irb'; require 'irb/completion'
#IRB.start

# main
include GLI::App

program_desc 'Simple ad-hoc tools for managing a google doc spreadsheet of books'

pre do |global_options, command, options, args|
  $config = YAML::load(File.open(CONFIG))
  $worksheet = open_worksheet $config
end

command :fix_names do |c|
  c.action do
    fix_names $worksheet
    $worksheet.save
  end
end

command :fix_isbns do |c|
  c.action do
    find_isbns $worksheet
    $worksheet.save
  end
end

command :export_for_goodreads do |c|
  c.flag [:c, :count,'count'], desc: 'number of recent records to dump, zero for all', default_value: 0, type: Numeric
  c.action do |global_options, options, args|
    export_for_goodreads $worksheet, $config, options[:count]
  end
end

command :dump_stats do |c|
  c.action do
    dump_stats $worksheet
  end
end

command :find_missing_from_goodreads do |c|
  c.action do
    find_missing_from_goodreads $worksheet, $config
  end
end

exit run(ARGV)

# optional whitelist of ISBN, one per line, for repeat runs on failed imports for example
__END__
