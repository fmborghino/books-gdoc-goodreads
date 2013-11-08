require 'rubygems'
require 'google_drive'
require 'openlibrary'
require 'csv'
require 'yaml'

config = YAML::load(File.open('./config.yml'))

def bail msg, code=1
  puts msg
  exit code
end

def open_worksheet config
  # gdoc login with app password
  begin
    session = GoogleDrive.login(config[:auth][:user], config[:auth][:pw])
  rescue Exception => e
    bail "login failed"
    puts e.message
  end

  # grab correct spreadsheet and worksheet
  spreadsheet = session.spreadsheet_by_title(config[:spreadsheet_name])
  bail "cannot find spreadsheet %s" % config[:spreadsheet_name] if spreadsheet.nil?
  worksheet = spreadsheet.worksheet_by_title(config[:worksheet_name])
  bail "cannot find worksheet %s" % config[:worksheet_name] if worksheet.nil?

  return worksheet
end

def fix_name name
  # Fix Author name: FOO, Bar -> Foo, Bar
  m = name.match(/^([A-Z]+), +(.+)/)
  return name if m.nil?
  return "%s, %s" % [ m[1].capitalize, m[2] ]
end

def fix_names w
  row = 2
  while not (name = w[row, 2]).empty?
    fixed = fix_name(name)
    puts "%-3s: %s\n     %s" % [row, name, fixed]
    w[row, 2] = fixed
    row += 1
  end
end

def find_isbns w
  client = Openlibrary::Client.new
  found = 0
  row = 2
  while not (name = w[row, 2]).empty?
    last_name = name.split(',').first
    # search api breaks on punctuation, remove it, keep spaces
    title = w[row, 1].gsub(/([^\w ])/, '')
    begin
      results = client.search({author: last_name, title: title})
      isbn = nil
      # some results do not have an isbn, so keep trying
      for r in results
        if not r.isbn.nil?
          isbn = r.isbn.first
          break
        end
      end
      puts "%-3s: %s | %s -> %s" % [row, last_name, title, isbn]
      found += 1 if not isbn.nil?
      w[row, 10] = isbn.to_s
    rescue Exception => e
      puts "%-3s: %s" % [row, e.message]
    end
    row += 1
  end
  puts "found %s, missing %s" % [found, (row - 1 - found)]
end

# goodreads format is (expects dates as %Y-%m-%d ISO 8601)
# Title, Author, ISBN, My Rating, Average Rating, Publisher, Binding, Year Published, Original Publication Year, Date Read, Date Added, Bookshelves, My Review
# my format is (dates are %m/%d/%Y)
# Title, Author, DateStart, DateFinish, Note, Days Open, Good book, Liked it, Ebook, ISBN
def export_for_goodreads w, config
  missing = DATA.readlines.map(&:chomp).map{|e| e.gsub(/\W/, '')}
  row = 2
  CSV.open(config[:csv_file_out], "wb") do |csv|
    csv << ['Title', 'Author', 'ISBN', 'My Rating', 'Average Rating', 'Publisher', 'Binding', 'Year Published', 'Original Publication Year', 'Date Read', 'Date Added', 'Bookshelves', 'My Review']
    while not w[row, 1].empty?
      isbn = w[row, 10]
      # use optional whiltelist in the DATA area below
      if not isbn.empty? and (missing.length == 0 or missing.include?(isbn))
        title = w[row, 1]
        # last name only
        author = w[row, 2].split(',').first
        rating = w[row, 8].count('*')
        date_read = w[row, 3]
        date_fmt = Date.strptime(date_read, '%m/%d/%Y').strftime('%F')
        csv << [ title, author, isbn, rating, "", "", "", "", "", date_fmt, "", "", ""]
        puts "%-3s: %-15s | %-10s | %s | %-13s | %s -> %s" % [row, title[0..14], author[0..9], rating, isbn[0..12], date_read, date_fmt]
      end
      row += 1
    end
  end
end

def dump_stats w
  row = 2
  isbns = Hash.new(0)
  while not w[row, 1].empty?
    isbn = w[row, 10]
    isbns[ isbn ] += 1
    print "row %s | %s" % [row, isbn] if not (isbn.empty? or isbn.length == 10 or isbn.length == 13)
    row += 1
  end
  puts "total records %s, unique records %s" % [row-1, isbns.length]
end

# goodreads import seems to have ignored some books, use the export from there to find which ones
def find_missing_from_goodreads w, config
  row = 2
  books = {}
  # build a hash of my books keyed by isbn
  while not w[row, 1].empty?
    isbn = w[row,10].to_s
    if not isbn.empty?
      books[ isbn ] = { title: w[row,1], author: w[row,2] }
    end
    row += 1
  end
  puts "master list books includes %s uniques" % books.length
  #
  # scan isbn (both 10 and 13) in export and remove those from my list
  # goodreads exported file has these headers
  # Book Id,Title,Author,Author l-f,Additional Authors,ISBN,ISBN13,My Rating,Average Rating,Publisher,Binding,Number of Pages,Year Published,Original Publication Year,Date Read,Date Added,Bookshelves,Bookshelves with positions,Exclusive Shelf,My Review,Spoiler,Private Notes,Read Count,Recommended For,Recommended By,Owned Copies,Original Purchase Date,Original Purchase Location,Condition,Condition Description,BCID
  # the ISBN fields look like
  # ="0374519994",="9780374519995" (or ="") which is broken and blows up the CSV parser, so strip those first
  open(config[:csv_file_in], "r").each do |l|
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
  puts "after removing matches from goodreads there are %s uniques" % books.length
  #books.each { |k, v| puts "%-20s | %-15s | %s " % [v[:title][0..19], v[:author][0..14], k] }
  books.each { |k, v| puts k }
end

#require 'irb'; require 'irb/completion'
#IRB.start

# main
worksheet = open_worksheet config

#fix_names worksheet; worksheet.save
#find_isbns worksheet; worksheet.save
#export_for_goodreads worksheet, config
dump_stats worksheet
#find_missing_from_goodreads worksheet, config

# optional whitelist of ISBN, one per line, for repeat runs on failed imports for example
__END__
