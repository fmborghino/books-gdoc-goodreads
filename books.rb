require 'rubygems'
require 'google_drive'
require 'openlibrary'
require 'csv'

# config
config = {
  auth: { user: "you@gmail.com", pw: "somesecret" },
  spreadsheet_name: "Books",
  worksheet_name: "Sheet 1",
  csv_file: "goodreads.csv"
}

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
  # FOO, Bar -> Foo, Bar
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
  missing = DATA.readlines.map &:chomp
  row = 2
  CSV.open(config[:csv_file], "wb") do |csv|
    csv << ['Title', 'Author', 'ISBN', 'My Rating', 'Average Rating', 'Publisher', 'Binding', 'Year Published', 'Original Publication Year', 'Date Read', 'Date Added', 'Bookshelves', 'My Review']
    while not w[row, 1].empty?
      isbn = w[row, 10]
      if not isbn.empty? and missing.include?(isbn)
        title = w[row, 1]
        rating = w[row, 8].count('*')
        date_read = w[row, 3]
        date_fmt = Date.strptime(date_read, '%m/%d/%Y').strftime('%F')
        csv << [ "", "", isbn, rating, "", "", "", "", "", date_fmt, "", "", ""]
        puts "%-3s: %-15s | %s | %s -> %s" % [row, title[0..15], rating, date_read, date_fmt]
      end
      row += 1
    end
  end
end

require 'irb'; require 'irb/completion'
IRB.start

# main
worksheet = open_worksheet config

#fix_names worksheet; worksheet.save
#find_isbns worksheet; worksheet.save
export_for_goodreads worksheet, config

__END__
9788700994713
9780756754730
9781407035192
009943508
8700566640
1404302433
9781870886123
9780450043772
1857231856
9990458359
9787536671805
1101001925
9785557082655
0575058811
4400695622
080728825
9781857231465
9780671833213
9780385289405
9781582342276
9781857992915
9780140085020
9781860499265
9780307379108
9780712651066
9780670857784
9780679443780
9780307236999
9780312853235
9780525444442
9780802714626
9780739481325
9780393333022
9780061806636
9780553374599
9780380715435
9781590302613
9780202120003
9780312064884
9780812550757
9780321344755
9780330233460
9780618346257
9780743220125
9780312856847
9780099285045
9781844131952
9780671618216
9781417700929
9780345339737
9780356501505
