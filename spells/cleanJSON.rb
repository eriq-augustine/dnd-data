require 'json'

KEY_RAW = '__raw__'
KEY_STRUCTURED = '__structured__'
KEY_ADDITIONAL = '__additional__'
KEY_OPTIONAL = '__optional__'
KEY_CONDITION = '__condition__'
KEY_CLASS = '__class__'
KEY_REQUIRED = '__required__'
KEY_SEE_DESCRIPTION = '__see_description__'
KEY_DISMISSABLE = '__dismissable__'
KEY_CONCENTRATION = '__concentration__'

KEY_NAME = 'name'
KEY_RAW_NAME = 'raw_name'
KEY_PAGE = 'page'
KEY_LEVEL = 'level'
KEY_SCHOOL = 'school'
KEY_COMPONENTS = 'components'
KEY_CASTING_TIME = 'casting_time'
KEY_RANGE = 'range'
KEY_DURATION = 'duration'
KEY_TARGET = 'target'
KEY_DESCRIPTION = 'description'

SPELL_PAGES_PATH = File.join('.', 'spells-pages.txt')
SPELL_RENAMES_PATH = File.join('.', 'spells-renames.txt')

CLASS_SHORT_NAMES = {
   'Brd' => 'Bard',
   'Clr' => 'Cleric',
   'Drd' => 'Druid',
   'Pal' => 'Paladin',
   'Rgr' => 'Ranger',
   'Sor' => 'Sorcerer',
   'Wiz' => 'Wizard',
}

# TEST(eriq): Done -- level, components, casting_time, range, duration

# TODO(eriq): target
# TODO(eriq): saving_throw
# TODO(eriq): spell_ressitence
# TODO(eriq): description

# TEST
def testKeySimple(spells, key)
   spells.map{|spell| spell[key]}.uniq().each{|row|
      puts row
   }
end

# TEST
def testKey(spells, key)
   spells.each{|spell|
      if (!spell.has_key?(key) || spell[key] == '')
         puts spell[KEY_NAME]
      end
   }

   puts '---'

   spells.map{|spell| spell[key]}.uniq().sort().each{|row|
      puts row
   }
end

# Returns: {spellName => page, ...}
def loadPages()
   pages = {}

   File.open(SPELL_PAGES_PATH, 'r'){|file|
      file.each{|line|
         line = line.strip()

         if (line == '')
            next
         end

         parts = line.split("\t").map{|part| part.strip()}
         pages[parts[0]] = parts[1]
      }
   }

   return pages
end

# Returns: {spellName => spellRename, ...}
def loadRenames()
   data = {}

   File.open(SPELL_RENAMES_PATH, 'r'){|file|
      file.each{|line|
         line = line.strip()

         if (line == '')
            next
         end

         parts = line.split("\t").map{|part| part.strip()}
         data[parts[0]] = parts[1]
      }
   }

   return data
end

def fixName(spells)
   renames = loadRenames()

   spells.each{|spell|
      name = spell[KEY_NAME]
      spell[KEY_RAW_NAME] = name

      if (renames.has_key?(name))
         spell[KEY_NAME] = renames[name]
      end
   }
end

def fixPage(spells)
   pages = loadPages()

   spells.each{|spell|
      if (!pages.has_key?(spell[KEY_RAW_NAME]))
         raise "Spell (#{spell[KEY_RAW_NAME]}) does not have page!"
      end

      spell[KEY_PAGE] = pages[spell[KEY_RAW_NAME]]
   }
end

def fixLevel(spells)
   spells.each{|spell|
      structured = {}

      spell[KEY_LEVEL].split(', ').each{|classLevel|
         classname, level = classLevel.split(/\s+/)
         level = level.to_i()

         if (classname == 'Sor/Wiz')
            structured['Sorcerer'] = level
            structured['Wizard'] = level
         else
            if (CLASS_SHORT_NAMES.has_key?(classname))
               classname = CLASS_SHORT_NAMES[classname]
            end
            structured[classname] = level
         end
      }

      spell[KEY_LEVEL] = {
         KEY_RAW => spell[KEY_LEVEL],
         KEY_STRUCTURED => structured
      }
   }
end

def fixComponents(spells)
   spells.each{|spell|
      structured = {
         KEY_REQUIRED => []
      }

      components = spell[KEY_COMPONENTS]
      if (components.end_with?('; see text'))
         structured[KEY_SEE_DESCRIPTION] = true
         components = components.sub('; see text', '').strip()
      end

      components.split(', ').map{|part| part.strip()}.each{|component|
         if (component.include?('/'))
            structured[KEY_REQUIRED] << component.split('/').map{|part| part.strip()}
         elsif (component.include?(' (Brd only)'))
            component = component.sub(' (Brd only)', '').strip()
            structured[KEY_REQUIRED] << {
               component => true,
               KEY_CONDITION => {
                  KEY_CLASS => 'Bard'
               }
            }
         elsif (match = component.match(/^\(([^\)]+)\)$/))
            if (!structured.has_key?(KEY_OPTIONAL))
               structured[KEY_OPTIONAL] = []
            end

            structured[KEY_OPTIONAL] << match[1]
         else
            structured[KEY_REQUIRED] << component
         end
      }

      spell[KEY_COMPONENTS] = {
         KEY_RAW => spell[KEY_COMPONENTS],
         KEY_STRUCTURED => structured
      }
   }
end

def fixCastingTime(spells)
   spells.each{|spell|
      structured = {}

      time = spell[KEY_CASTING_TIME]
      if (match = time.match(/(?:; | or )?see text$/i))
         structured[KEY_SEE_DESCRIPTION] = true
         time = time.sub(match[0], '').strip()
      end

      case time
      when 'One minute'
         time = '1 minute'
      when 'At least 10 minutes'
         time = '>= 10 minutes'
      when '1 minute or longer'
         time = '>= 1 minute'
      when '1 minute/lb. created'
         time = '1 min/lb'
      end

      structured[KEY_CASTING_TIME] = time

      spell[KEY_CASTING_TIME] = {
         KEY_RAW => spell[KEY_CASTING_TIME],
         KEY_STRUCTURED => structured
      }
   }
end

def fixRange(spells)
   spells.each{|spell|
      structured = {}

      range = spell[KEY_RANGE]
      if (match = range.match(/(?:; | or )?see text$/i))
         structured[KEY_SEE_DESCRIPTION] = true
         range = range.sub(match[0], '').strip()
      end

      range = range.gsub(/ft\./i, 'feet')
      range = range.gsub(/one/i, '1')

      case range
      when 'Long (400 feet + 40 feet/level)'
         range = 'Long'
      when 'Medium (100 feet + 10 feet/level)', 'Medium (100 feet + 10 feet level)'
         range = 'Medium'
      when 'Close (25 feet + 5 feet/2 levels)'
         range = 'Close'
      when 'Close (25 feet + 5 feet/2 levels)/ 100 feet'
         range = 'Close'
      when 'Anywhere within the area to be warded'
         range = 'In Warded Area'
      when 'Up to 10 feet/level'
         range = '<= 10 feet/level'
      when 'Personal and touch'
         range = 'Personal and Touch'
      when 'Personal or close (25 feet + 5 feet/2 levels)'
         range = 'Personal or Close'
      when 'Personal or touch'
         range = 'Personal or Touch'
      end

      structured[KEY_RANGE] = range

      spell[KEY_RANGE] = {
         KEY_RAW => spell[KEY_RANGE],
         KEY_STRUCTURED => structured
      }
   }
end

def fixDuration(spells)
   spells.each{|spell|
      structured = {}

      duration = spell[KEY_DURATION]

      if (match = duration.match(/(?:; | or )?see text$/i))
         structured[KEY_SEE_DESCRIPTION] = true
         duration = duration.sub(match[0], '').strip()
      end

      if (match = duration.match(/; see text for cause fear$/i))
         structured[KEY_SEE_DESCRIPTION] = true
         duration = duration.sub(match[0], '').strip()
      end

      if (match = duration.match(/\s+\(D\)/))
         structured[KEY_DISMISSABLE] = true
         duration = duration.sub(match[0], '').strip()
      end

      if (match = duration.match(/\s+or until discharged/i))
         structured[KEY_DISMISSABLE] = true
         duration = duration.sub(match[0], '').strip()
      end

      if (match = duration.match(/\s+or less/i))
         structured[KEY_SEE_DESCRIPTION] = true
         duration = duration.sub(match[0], '').strip()
      end

      if (match = duration.match(/\s+or until (completed|expended|used|you return to your body|all beams are exhausted)/i))
         structured[KEY_SEE_DESCRIPTION] = true
         duration = duration.sub(match[0], '').strip()
      end

      if (match = duration.match(/^Concentration,?\s*/i))
         structured[KEY_CONCENTRATION] = true
         duration = duration.sub(match[0], '').strip()
      end

      duration = duration.gsub(/one/i, '1')
      duration = duration.gsub(/two/i, '2')
      duration = duration.gsub(/seven/i, '7')
      duration = duration.gsub(/sixty/i, '60')
      duration = duration.gsub('min./', 'min/')
      duration = duration.gsub('minute/', 'min/')
      duration = duration.gsub('/ level', '/lvl')
      duration = duration.gsub('/level', '/lvl')
      duration = duration.gsub('hour/', 'hr/')
      duration = duration.gsub('caster level', 'lvl')
      duration = duration.gsub(' /', '/')
      duration = duration.gsub('up to ', '')
      duration = duration.gsub(/^\+ (\d)/, '+\1')
      duration = duration.gsub(' (apparent time)', '')
      duration = duration.gsub(' plus 12 hours', '')
      duration = duration.gsub(', then', '; then')
      duration = duration.gsub('Permanent until discharged', 'Until Triggered')
      duration = duration.gsub(' (1 round)', '')
      duration = duration.gsub(' (1d4 rounds)', '')
      duration = duration.gsub(' (1d6 rounds)', '')
      duration = duration.gsub('(1 round/lvl) or instantaneous', 'Instantaneous or 1 round/lvl')
      duration = duration.gsub('(maximum 10 rounds)', '10 rounds')
      duration = duration.gsub('1 usage per 2 levels', '1 usage/(2 lvl)')
      duration = duration.gsub('round per three levels', 'round/(3 lvl)')
      duration = duration.gsub('(4 rounds)', '4 rounds')
      duration = duration.gsub(', whichever comes first', '')
      duration = duration.gsub('1d4 rounds or 1 round', '1 or 1d4 rounds')
      duration = duration.gsub(' or concentration (1 round/lvl)', ' or 1 round/lvl')
      duration = duration.gsub('Instantaneous/1 hour', 'Instantaneous; 1 hour')
      duration = duration.gsub('1 round/lvl and concentration + 3 rounds', '1 round/lvl; +3 rounds')
      duration = duration.gsub('30 minutes and 2d6 rounds', '30 minutes; 2d6 rounds')

      duration = duration.gsub('min.', 'minute')

      if (match = duration.match(/(?:; | or )?see text$/i))
         structured[KEY_SEE_DESCRIPTION] = true
         duration = duration.sub(match[0], '').strip()
      end

      case duration
      when '1d4+1 rounds, or 1d4+1 rounds after creatures leave the smoke cloud'
         duration = '1d4+1 rounds'
      when 'IInstantaneous/10 minutes per HD of subject'
         duration = 'Instantaneous; 10 min/HD'
      when 'No more than 1 hr/lvl (destination is reached)'
         duration = '1 hr/lvl'
      when 'Permanent; until released or 1d4 days + 1 day/lvl'
         duration = 'Permanent until discharged; 1d4 days + 1 day/lvl'
      when 'Until expended or 10 min/lvl'
         duration = '10 min/lvl or until expended'
      when 'Until landing or 1 round/lvl'
         duration = '1 round/lvl or until landed'
      when 'Up to 1 round/lvl'
         duration = 'Up to 1 round/lvl'
      end

      structured[KEY_DURATION] = duration

      spell[KEY_DURATION] = {
         KEY_RAW => spell[KEY_DURATION],
         KEY_STRUCTURED => structured
      }
   }
end

def main(inPath, outPath)
   spells = JSON.parse(File.read(inPath))

   fixName(spells)
   fixPage(spells)
   fixLevel(spells)
   fixComponents(spells)
   fixCastingTime(spells)
   fixRange(spells)
   fixDuration(spells)

   File.open(outPath, 'w'){|file|
      file.puts(JSON.pretty_generate(spells))
   }
end

def loadArgs(args)
   if (args.size() != 2 || args.map{|arg| arg.gsub('-', '').downcase()}.include?('help'))
      puts "USAGE: ruby #{$0} <input file> <output file>"
      exit(1)
   end

   return args
end

if ($0 == __FILE__)
   main(*loadArgs(ARGV))
end
