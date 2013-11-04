require 'rubygems'
require 'google_drive'

# config
auth = { user: "you@gmail.com", pw: "somesecret" }
spreadsheet_name = "Books"
worksheet_name = "Sheet 1"

def bail msg, code=1
  puts msg
  exit code
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

# login with app password
begin
  session = GoogleDrive.login(auth[:user], auth[:pw])
rescue Exception => e
  bail "login failed"
  puts e.message
end

# grab correct spreadsheet and worksheet
spreadsheet = session.spreadsheet_by_title(spreadsheet_name)
bail "cannot find spreadsheet %s" % spreadsheet_name if spreadsheet.nil?
worksheet = spreadsheet.worksheet_by_title(worksheet_name)
bail "cannot find worksheet %s" % worksheet_name if worksheet.nil?

fix_names worksheet
worksheet.save
