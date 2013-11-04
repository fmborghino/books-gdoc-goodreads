require 'rubygems'
require 'google_drive'
require 'openlibrary'

# config
config = {
  auth: { user: "you@gmail.com", pw: "somesecret" },
  spreadsheet_name: "Books",
  worksheet_name: "Sheet 1"
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
      w[row, 11] = isbn.to_s
    rescue Exception => e
      puts "%-3s: %s" % [row, e.message]
    end
    row += 1
  end
  puts "found %s, missing %s" % [found, (row - 1 - found)]
end

#require 'irb'; require 'irb/completion'
#IRB.start

# main
worksheet = open_worksheet config

#fix_names worksheet
find_isbns worksheet

worksheet.save
