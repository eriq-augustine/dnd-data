require 'fileutils'
require 'json'
require 'openssl'
require 'open-uri'
require 'net/http'
require 'uri'

require 'nokogiri'

CACHE_DIR = 'cache'
SKIP_PAGES = [
   # Race
   'https://dnd-wiki.org/wiki/SRD:Lizardfolk',
   # Many strike-throughs
   'https://dnd-wiki.org/wiki/SRD:Blue',
   'https://dnd-wiki.org/wiki/SRD:Deinonychus',
   'https://dnd-wiki.org/wiki/SRD:Gelatinous_Cube',
   'https://dnd-wiki.org/wiki/SRD:Megaraptor',
   # Multiple disjunctions in statblock.
   'https://dnd-wiki.org/wiki/SRD:Ghaele',
   # Multiple variants in same creature
   'https://dnd-wiki.org/wiki/SRD:Large_Animated_Object',
   'https://dnd-wiki.org/wiki/SRD:Huge_Animated_Object',
   'https://dnd-wiki.org/wiki/SRD:Colossal_Animated_Object',
   'https://dnd-wiki.org/wiki/SRD:Gargantuan_Animated_Object',
   # Strange thing with lots of exceptions.
   'https://dnd-wiki.org/wiki/SRD:Psicrystal'
]

# Cleansing subs.
CHARACTER_SUBS = [
   ['–', '-'],
   ['—', '-'],
   ['−', '-'],
   ['’', "'"]
]

KEY_NAME = 'name'
KEY_HEADER = '__header__'
KEY_PARSED = '__parsed__'
KEY_RAW = '__raw__'
KEY_STATBLOCK = 'statblock'

CREATURE_SIZES = [
   'fine',
   'diminutive',
   'tiny',
   'small',
   'medium',
   'large',
   'huge',
   'gargantuan',
   'colossal'
]

CREATURE_TYPES = [
   'aberration',
   'animal',
   'construct',
   'dragon',
   'elemental',
   'fey',
   'giant',
   'humanoid',
   'magical beast',
   'monstrous humanoid',
   'ooze',
   'outsider',
   'plant',
   'undead',
   'vermin'
]

CREATURE_SUBTYPES = [
   'air',
   'aquatic',
   'archon',
   'chaotic',
   'cold',
   'dwarf',
   'earth',
   'elf',
   'evil',
   'extraplanar',
   'fire',
   'gnome',
   'goblinoid',
   'good',
   'halfling',
   'human',
   'incorporeal',
   'lawful',
   'maenad',
   'native',
   'orc',
   'psionic',
   'reptilian',
   'shapechanger',
   'water',
   'xeph'
]

def fetchLink(url)
   cachePath = File.join(CACHE_DIR, url.gsub('/', '_'))
   FileUtils.mkdir_p(CACHE_DIR)

   if (File.exists?(cachePath))
      contents = nil
      File.open(cachePath, 'r'){|file|
         contents = file.read()
      }
      return contents
   end

   contents = nil
   # dnd-wiki has some SSL issues.
   open(URI.parse(url), {ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE}){|page|
      contents = page.read()
   }

   File.open(cachePath, 'w'){|file|
      file.puts(contents)
   }
   return contents
end

def clean(text)
   text = text.strip().gsub(/\s+/, ' ')
   CHARACTER_SUBS.each{|sub| text = text.gsub(sub[0], sub[1])}
   return text
end

def parseName(doc, data)
   data[KEY_NAME] = doc.at_css('h1#firstHeading.firstHeading').text().strip().sub(/^SRD:/, '')
end

def normalizeSize(text)
   text = text.downcase().strip()

   if (!CREATURE_SIZES.include?(text))
      raise "Unknown size: '#{text}'."
   end

   return text
end

def normalizeType(text)
   text = text.downcase().strip()

   if (!CREATURE_TYPES.include?(text))
      raise "Unknown type: '#{text}'."
   end

   return text
end

def normalizeSubtype(text)
   text = text.downcase().strip()

   if (!CREATURE_SUBTYPES.include?(text))
      raise "Unknown subtype: '#{text}'."
   end

   return text
end

# The text should be a standard roll specification
def parseHitDice(rollSpecification)
   value = rollSpecification.gsub(/(d\d+)[\+\-]\d+/, '\1')
   value = value.gsub(/d\d+/, '')

   while (match = value.match(/\((\d+)\/(\d+)\)/))
      value = "#{match[1].to_i().to_f() / match[2].to_i()}"
   end

   while (match = value.match(/(\d+\.?\d*) \+ (\d+\.?\d*)/))
      value = "#{match[1].to_f() + match[2].to_f()}"
   end

   if (!value.match(/^\d+\.?\d*$/))
      throw "Bad roll specification for HD: '#{rollSpecification}'."
   end

   if (value.match(/^\d+(\.0)?$/))
      return value.to_i()
   else
      return value.to_f()
   end
end

# The stat block is the most important part of the page.
def parseStatBlock(doc, data)
   raw = {}
   parsed = {}

   stats = {
      KEY_RAW => {},
      KEY_PARSED => {}
   }

   table = doc.at_css('div#mw-content-text > table.monstats')
   if (table == nil)
      # TEST
      # raise "No statblock found. Is this a monster? (Race meybe?)"
      return
   end

   firstRow = true
   table.css('tr').each{|row|
      if (firstRow)
         firstRow = false

         val = row.css('th')[1]
         if (val == nil)
            next
         end

         raw[KEY_HEADER] = clean(val.text())
      else
         header = clean(row.at_css('th').text().strip().sub(/:\s*/, '').downcase().sub(/\s+/, '_'))
         value = clean(row.at_css('td').text().downcase())

         raw[header] = value

         case header
         when 'size/type'
            value = value.downcase()

            match = value.match(/^(\S+)\s+([^\(]+)(\s+\(.+\))?$/)
            if (match == nil)
               raise "Size/Type match failed: '#{value}'."
            end

            parsed['size'] = normalizeSize(match[1])
            parsed['type'] = normalizeType(match[2])

            if (match[3] != nil)
               subtypes = match[3].strip().sub(/^\(/, '').sub(/\)$/, '').strip().split(', ')
               parsed['subtype'] = subtypes.map{|subtype| normalizeSubtype(subtype)}
            end
         when 'hit_dice'
            value = value.sub(/\s+\(\d+\s+hp\)$/, '')
            value = value.gsub(/(\d+\/\d+)\s+/, '(\1)')
            value = value.gsub(/d(\d+)\s+\+\s+(\d+)$/, 'd\1+\2')
            value = value.gsub(/\s+plus\s+/, ' + ')
            value = value.gsub(/(\d+d\d+)\+(\d+d\d+)/, '\1 + \2')

            parsed['hit_dice'] = parseHitDice(value)
            parsed['hit_points'] = value
         when 'initiative'
            parsed[header] = value.to_i()
         when 'speed'
            speed = {}

            if (value.include?("can't run"))
               speed['run'] = false
            end

            value = value.gsub(/\s+\(\d+\s+square(s)?(; can't run)?\)/, '')
            value = value.gsub(/\s+ft(\.)?/, '')
            value = value.gsub(';', ',')

            value.split(', ').each{|part|
               part = part.strip()

               if (match = part.match(/^(\d+)\s+in\s+(.+)$/))
                  speed[match[2]] = match[1].to_i()
               elsif (match = part.match(/^base\s+speed\s+(\d+)$/))
                  speed['base'] = match[1].to_i()
               elsif (match = part.match(/^base\s+land\s+speed\s+(\d+)$/))
                  speed['base'] = match[1].to_i()
               elsif (match = part.match(/^climb\s+(\d+)$/))
                  speed['climb'] = match[1].to_i()
               elsif (match = part.match(/^swim\s+(\d+)$/))
                  speed['swim'] = match[1].to_i()
               elsif (match = part.match(/^swim\s+speed\s+(\d+)$/))
                  speed['swim'] = match[1].to_i()
               elsif (match = part.match(/^burrow\s+(\d+)$/))
                  speed['burrow'] = match[1].to_i()
               elsif (match = part.match(/^fly\s+(\d+)\s*\(([a-z]+)\)$/))
                  speed['fly'] = match[1].to_i()
                  # maneuverability
                  speed['fly_type'] = match[2].to_i()
               elsif (match = part.match(/^fly\s+(\d+)$/))
                  speed['fly'] = match[1].to_i()
               elsif (match = part.match(/^(\d+)\s+wheels$/))
                  speed['wheels'] = match[1].to_i()
               elsif (match = part.match(/^(\d+)\s+legs$/))
                  speed['legs'] = match[1].to_i()
               elsif (match = part.match(/^(\d+)\s+multiple\s+legs$/))
                  speed['multiple_legs'] = match[1].to_i()
               # Last few exceptions.
               elsif (part == 'base fly speed 20 (perfect)')
                  speed['fly'] = 20
                  speed['fly_type'] = 'perfect'
               elsif (part == 'fly 15 (perfect) in chainmail')
                  speed['chainmail'] = {
                     'fly' => 15,
                     'fly_type' => 'perfect'
                  }
               elsif (part == 'swim 30 in breastplate')
                  speed['breastplate'] = {
                     'swim' => 30
                  }
               elsif (part == 'fly 40 (average) in plate barding')
                  speed['plate barding'] = {
                     'fly' => 40,
                     'fly_type' => 'average'
                  }
               elsif (match = part.match(/^(\d+)$/))
                  speed['base'] = match[1].to_i()
               else
                  raise "Unknown speed pattern: '#{part}'."
               end
            }

            parsed['speed'] = speed
         when 'armor_class'
            value = value.sub(',,', ',')
            value = value.sub(/^ac\s+/, '')

            ac = {}
            mods = {}

            if (match = value.match(/^(\d+)\s+\(([^\(]+)\),\s+touch\s+(-?\d+),\s+flat-footed\s+(-?\d+)$/))
               ac['total'] = match[1].to_i()
               ac['touch'] = match[3].to_i()
               ac['flat-footed'] = match[4].to_i()

               match[2].split(',').each{|part|
                  part = part.strip()

                  if (partMatch = part.match(/^([+\-]?\d+)\s+size$/))
                     mods['size'] = partMatch[1].to_i()
                  elsif (partMatch = part.match(/^([+\-]?\d+)\s+dex$/))
                     mods['dex'] = partMatch[1].to_i()
                  elsif (partMatch = part.match(/^([+\-]?\d+)\s+natural(\s+armor)?$/))
                     mods['natural'] = partMatch[1].to_i()
                  elsif (partMatch = part.match(/^([+\-]?\d+)\s+deflection$/))
                     mods['deflection'] = partMatch[1].to_i()
                  elsif (partMatch = part.match(/^([+\-]?\d+)\s+dodge$/))
                     mods['dodge'] = partMatch[1].to_i()
                  elsif (partMatch = part.match(/^([+\-]?\d+)\s+insight$/))
                     mods['insight'] = partMatch[1].to_i()
                  elsif (part == 'ring of protection +1')
                     mods['ring of protection +1'] = 1
                  elsif (partMatch = part.match(/^([+\-]?\d+)\s+(.+)$/))
                     mods[partMatch[2]] = partMatch[1].to_i()
                  else
                     raise "Unknown AC mod pattern: '#{part}'."
                  end
               }
            elsif (value == '14 (-1 size, +5 natural), touch 9, flat-footed - (see text)')
               ac['total'] = 14
               ac['touch'] = 9
               mods['size'] = -1
               mods['natural'] = 5
            elsif (value == '14 (+2 dex, +2 size, touch 14, flat-footed 12')
               ac['total'] = 14
               ac['touch'] = 14
               ac['flat-footed'] = 12
               mods['dex'] = 2
               mods['size'] = 2
            elsif (value == '23 (+1 dex, +6 natural, +4 scale mail, +2 heavy shield, touch 11, flat-footed 22')
               ac['total'] = 23
               ac['touch'] = 11
               ac['flat-footed'] = 22
               mods['dex'] = 1
               mods['natural'] = 6
               mods['scale mail'] = 4
               mods['heavy shield'] = 2
            else
               raise "Non-parsed AC: '#{value}'."
            end

            if (mods != {})
               ac['mods'] = mods
            end

            parsed['armor_class'] = ac
         when 'base_attack/grapple'
            if (match = value.match(/^([+\-]?\d+)\/([+\-]?\d+)\*?$/))
               parsed['base_attack'] = match[1].to_i()
               parsed['grapple'] = match[2].to_i()
            elsif (match = value.match(/^([+\-]?\d+)\/-$/))
               parsed['base_attack'] = match[1].to_i()
            elsif (value == '+1/-11 (+1 when attached)')
               # Stirge
               parsed['base_attack'] = 1
               parsed['grapple'] = -11
            else
               raise "Non-parsed Base Attack / Grapple: '#{value}'."
            end
         when 'attack'
            value = value.gsub('3d6 sonic or 3d6 electricity', '3d6 sonic/electricity')
            value = value.gsub('*', '')

            attacks = []
            value.split(' or ').map{|part| part.strip()}.each{|part|
               if (['-'].include?(part))
                  next
               else
                  attacks << part
               end
            }

            if (attacks.size() > 0)
               parsed['attack'] = attacks
            end
         when 'full_attack'
            value = value.gsub('3d6 sonic or 3d6 electricity', '3d6 sonic/electricity')
            value = value.gsub(/^\+2 slams/, '2 slams')
            value = value.gsub('*', '')
            value = value.gsub(';', ' or ')

            attacks = []
            value.split(' or ').map{|part| part.strip()}.each{|part|
               if (['', '-'].include?(part))
                  next
               else
                  attacks << part
               end
            }

            if (attacks.size() > 0)
               parsed['full_attack'] = attacks
            end
         when 'space/reach'
            parts = value.split('./')
            if (parts.size() != 2)
               raise "Non-parsed Space / Reach: '#{value}'."
            end

            size, rawReach = parts

            size = size.gsub(' (4 squares)', '')
            size = size.gsub('2-1/2 ft', '2.5 ft')
            size = size.gsub(/\s+ft\s*$/, '').to_i()

            rawReach = rawReach.gsub('ft.', 'ft')
            rawReach = rawReach.gsub('15ft', '15 ft')

            reach = {}
            if (match = rawReach.match(/^(\d+)\s+ft\s*$/))
               reach['base'] = match[1].to_i()
            elsif (match = rawReach.match(/^(\d+)\s+ft\s+\(([^\)]+)\)\s*$/))
               reach['base'] = match[1].to_i()

               match[2].split(',').map{|part| part.strip()}.each{|part|
                  if (partMatch = part.match(/^(\d+)\s+ft\s+(.+)\s*$/))
                     reach[partMatch[2]] = partMatch[1].to_i()
                  else
                     raise "Non-parsed Reach component: '#{part}'."
                  end
               }
            else
               raise "Non-parsed Reach: '#{rawReach}'."
            end

            parsed['size'] = size
            if (reach != {})
               parsed['reach'] = reach
            end
         when 'special_attacks'
            value = value.gsub('paralyis', 'paralysis')
            value = value.gsub('psi-like abilities)', 'psi-like abilities')

            attacks = []
            value.split(',').map{|part| part.strip()}.each{|part|
               if (['', '-', 'none', 'see text'].include?(part))
                  next
               else
                  attacks << part
               end
            }

            if (attacks.size() > 0)
               parsed['special_attacks'] = attacks
            end
         when 'special_qualities'
            value = value.gsub('60ft', '60 ft')
            value = value.gsub('lowlight', 'low-light')
            value = value.gsub('see in darkness', 'darkvision')
            value = value.gsub('twoweapon', 'two-weapon')

            value = value.sub('resistance to electricity 10, fire 10, and sonic 10', 'electricity resistance (10) ; fire resistance (10) ; sonic resistance (10)')
            value = value.sub('resistance to acid 10, cold 10, and electricity 10', 'acid resistance (10) ; cold resistance (10) ; electricity resistance (10)')
            value = value.sub('resistance to acid 5, cold 5, and electricity 5', 'acid resistance (5) ; cold resistance (5) ; electricity resistance (5)')
            value = value.sub('resistance to cold 5, electricity 5, and fire 5', 'cold resistance (5) ; electricity resistance (5) ; fire resistance (5)')
            value = value.sub('resistance to acid, cold, and electricity 5', 'acid resistance (5) ; cold resistance (5) ; electricity resistance (5)')
            value = value.sub('resistance to acid 10, cold 10, and fire 10', 'acid resistance (10) ; cold resistance (10) ; fire resistance (10)')
            value = value.sub('resistance to cold 10 and electricity 10', 'cold resistance (10) ; electricity resistance (10)')
            value = value.sub('resistance to electricity 10 and fire 10', 'electricity resistance (10) ; fire resistance (10)')
            value = value.sub('resistance to cold 10 and sonic 10', 'cold resistance (10) ; sonic resistance (10)')
            value = value.sub('resistance to acid 10 and cold 10', 'acid resistance (10) ; cold resistance (10)')
            value = value.sub('resistance to acid 10 and fire 10', 'acid resistance (10) ; fire resistance (10)')
            value = value.sub('resistance to cold 10 and fire 10', 'cold resistance (10) ; fire resistance (10)')
            value = value.sub('resistance to cold, and fire 5', 'cold resistance (5) ; fire resistance (5)')
            value = value.sub('resistance to cold and fire 5', 'cold resistance (5) ; fire resistance (5)')
            value = value.sub('resistance to electricity 10', 'electricity resistance (10)')
            value = value.sub('resistance to electricity 15', 'electricity resistance (15)')
            value = value.sub('resistance to cold 10', 'cold resistance (10)')
            value = value.sub('resistance to fire 10', 'fire resistance (10)')
            value = value.sub('resistance to fire 5', 'fire resistance (5)')
            value = value.sub('resistance to charm', 'charm resistance')

            value = value.sub('immunity to fire, poison, disease, energy drain, and ability damage', 'fire immunity ; poison immunity ; disease immunity ; energy drain immunity ; ability damage immunity')
            value = value.sub('immune to cold, electricity, polymorph, and mind-affecting attacks', 'cold immunity ; electricity immunity ; polymorph immunity ; mind-affecting attack immunity')
            value = value.sub('immunity to fire, cold, charm, sleep, and fear', 'fire immunity ; cold immunity ; charm immunity ; sleep immunity ; fear immunity')
            value = value.sub('immunity to critical hits and transformation', 'critical hit immunity ; transformation immunity')
            value = value.sub('immunity to poison, petrification, and cold', 'poison immunity ; petrification immunity ; cold immunity')
            value = value.sub('immunity to poison, charm, and compulsion', 'poison immunity ; charm immunity ; compulsion immunity')
            value = value.sub('immunity to electricity, fire, and poison', 'electricity immunity ; fire immunity ; poison immunity')
            value = value.sub('immunity to acid, cold, and petrification', 'acid immunity ; cold immunity ; petrification immunity')
            value = value.sub('immunity to acid, electricity, and poison', 'acid immunity ; electricity immunity ; poison immunity')
            value = value.sub('immunity to electricity and petrification', 'electricity immunity ; petrification immunity')
            value = value.sub('immunity to fire, sleep, and paralysis', 'fire immunity ; sleep immunity ; paralysis immunity')
            value = value.sub('immunity to sleep and charm effects', 'sleep immunity ; charm effect immunity')
            value = value.sub('immunity to electricity and poison', 'electricity immunity ; poison immunity')
            value = value.sub('immunity to sleep and paralysis', 'sleep immunity ; paralysis immunity')
            value = value.sub('immunity to fire and poison', 'fire immunity ; poison immunity')
            value = value.sub('immunity to fire and cold', 'fire immunity ; cold immunity')
            value = value.sub('immunity to cold and fire', 'cold immunity ; fire immunity')
            value = value.sub('immune to weapon damage', 'weapon damage immunity')
            value = value.sub('immunity to electricity', 'electricity immunity')
            value = value.sub('immunity to acid', 'acid immunity')
            value = value.sub('immunity to cold', 'cold immunity')
            value = value.sub('immunity to fire', 'fire immunity')
            value = value.sub('immunity to magic', 'magic immunity')
            value = value.sub('immunity to poison', 'poison immunity')
            value = value.sub('immunity to psionics', 'psionics immunity')

            value = value.gsub(/\bdr\s+(\d+)\/\s*/, 'damage reduction \1/')
            value = value.gsub(/\bsr\s+(\d+)/, ' ; spell resistance (\1) ; ')
            value = value.gsub(/spell resistance\s+(\d+)/, ' ; spell resistance (\1) ; ')
            value = value.gsub(' ft.', ' ft')
            value = value.gsub(' ft', '')

            value = value.gsub(',', ';')

            qualities = []
            value.split(';').map{|part| part.strip()}.each{|part|
               part.sub(/\.$/, '')

               if (['', '-', 'also see text', 'none'].include?(part))
                  next
               else
                  qualities << part
               end
            }

            if (qualities.size() > 0)
               parsed['special_qualities'] = qualities
            end
         when 'saves'
            saves = {}
            if (match = value.match(/^fort\s+([+\-]\d+)\*?, ref\s+([+\-]\d*)\*?, will\s+([+\-]\d+)\*?$/))
               saves['fortitude'] = match[1].to_i()

               # It is possible to not have a reflex save if the creature cannot move.
               if (match[2] != '-')
                  saves['reflex'] = match[2].to_i()
               end

               saves['will'] = match[3].to_i()
            elsif (match = value.match(/^fort\s+([+\-]\d+)\*? \(([+\-]\d+) against poison\), ref\s+([+\-]\d*)\*?, will\s+([+\-]\d+)\*?$/))
               saves['fortitude'] = match[1].to_i()
               saves['fortitude_poison'] = match[2].to_i()

               # It is possible to not have a reflex save if the creature cannot move.
               if (match[3] != '-')
                  saves['reflex'] = match[3].to_i()
               end

               saves['will'] = match[4].to_i()
            else
               raise "Non-parsed saves: '#{value}'."
            end

            parsed['saves'] = saves
         when 'abilities'
            value = value.gsub(' (with gloves)', '')
            value = value.gsub(' (with headband)', '')
            value = value.gsub(' -, ', ' 0, ')
            value = value.gsub(/ -$/, ' 0')
            value = value.gsub(' , ', ' 0, ')
            value = value.gsub('*', '')

            abilities = {}

            if (match = value.match(/^str (\d+), dex (\d+), con (\d+), int (\d+), wis (\d+), cha (\d+)$/))
               abilities['strength'] = match[1].to_i()
               abilities['dexterity'] = match[2].to_i()
               abilities['constitution'] = match[3].to_i()
               abilities['intelligence'] = match[4].to_i()
               abilities['wisdom'] = match[5].to_i()
               abilities['charisma'] = match[6].to_i()
            else
               raise "Non-parsed abilities: '#{value}'."
            end

            parsed['abilities'] = abilities
         when 'skills'
            value = value.gsub('move silently +10, (+3 following tracks)', 'move silently +10 (+3 following tracks)')
            value = value.gsub(',', ';')
            value = value.gsub('*', '')
            value = value.gsub(/\+\s+(\d)/, '+\1')

            while (value.sub!(/(\([^\)]+);/, '\1,'))
            end

            value = value.gsub('spot +16 survival +16', 'spot +16 ; survival +16')
            value = value.gsub('spot +11 swim +12', 'spot +11 ; swim +12')

            skills = {}
            value.split(';').map{|part| part.strip()}.each{|part|
               # Correct strikethroughs (double numbers).
               part = part.sub(/([+\-]\d+)\s+([+\-]\d+)$/, '\2')

               if (part == '-')
                  next
               elsif (match = part.match(/^(.+) ([+\-]?\d+)$/))
                  skills[match[1]] = match[2].to_i()
               elsif (match = part.match(/^(.+) ([+\-]?\d+) \(([+\-]?\d+) (.+), ([+\-]?\d+) (.+)\)$/))
                  skills[match[1]] = {
                     'base' => match[2].to_i(),
                     match[4] => match[3].to_i(),
                     match[6] => match[5].to_i(),
                  }
               elsif (match = part.match(/^(.+) ([+\-]?\d+) \(([+\-]?\d+) (.+)\)$/))
                  skills[match[1]] = {
                     'base' => match[2].to_i(),
                     match[4] => match[3].to_i(),
                  }
               else
                  raise "Non-parsed skill component: '#{part}'."
               end
            }

            if (skills != {})
               parsed['skills'] = skills
            end
         when 'feats'
            value = value.gsub('blind fight', 'blind-fight')
            value = value.gsub(',', ';')
            value = value.gsub(' plus human extra feat', '; human extra feat')

            while (value.sub!(/(\([^\)]+);/, '\1,'))
            end

            feats = []
            value.split(';').map{|part| part.strip()}.each{|part|
               part = part.sub(/\.$/, '')
               part = part.sub(/^and\s+/, '')

               # We don't care about bonus feats.
               part = part.sub(/\s*b$/, '')

               if (['', '-'].include?(part))
                  next
               else
                  feats << part
               end
            }

            feats = feats.uniq()
            if (feats.size() > 0)
               parsed['feats'] = feats
            end
         when 'environment'
            value = value.sub(/\s*\.$/, '')
            value = value.sub(/a(n)?\s+/, '')
            value = value.gsub(/(\S)\(/, '\1 (')

            parsed['environment'] = value
         when 'organization'
            value = value.gsub(' hyena; ', ' hyena -- ')
            value = value.gsub('solitary solitary', 'solitary')
            value = value.gsub('solitary (1)', 'solitary')
            value = value.gsub(',', ';')
            value = value.gsub('.', '')

            while (value.sub!(/(\([^\)]+);/, '\1 , '))
            end

            value = value.gsub(') or ', ') ; ')
            value = value.gsub(/^(\S+) or /, '\1 ; ')
            value = value.gsub(/\s+,\s+/, ', ')

            orgs = []
            value.split(';').map{|part| part.strip()}.each{|part|
               part = part.sub(/^\s*or\s+/, '')

               if (part == 'none')
                  next
               end

               orgs << part
            }

            if (orgs.size() > 0)
               parsed['organization'] = orgs
            end
         when 'challenge_rating'
            value = value.sub(' (see text)', '')
            value = value.sub('(normal)', '')
            value = value.sub(') or ', ') ; ')
            value = value.sub('4 (5 with irresistible dance)', '4 ; 5 (with irresistible dance)')

            parsed['challenge_rating'] = value.split(';').map{|part| part.strip()}
         when 'treasure'
            value = value.gsub('1/10th', '1/10')
            value = value.gsub(/\bplus\b/, ' ; ')
            value = value.gsub(/\band\b/, ' ; ')
            value = value.gsub(' (+5 str=bonus)', '')
            value = value.gsub('50%', '1/2')
            value = value.gsub('double', '2x')
            value = value.gsub('triple', '3x')
            value = value.gsub(/\bhalf /, '1/2 ')
            value = value.gsub(' (including equipment)', '')
            value = value.gsub(/ \(including (.+)\)/, ' ; \1')
            value = value.gsub('possessions noted below', '')

            treasure = []
            value.split(/[,;]\s+/).map{|part| part.strip()}.each{|part|
               part = part.sub(/^and /, '')

               if (['', 'none', 'possessions noted below'].include?(part))
                  next
               else
                  treasure << part
               end
            }

            if (treasure.size() > 0)
               parsed['treasure'] = treasure
            end
         when 'alignment'
            value = value.sub(/\.$/, '')

            if (value == 'usually chaotic good(wood: usually neutral)')
               value = 'usually chaotic good (wood: usually neutral)'
            end

            parsed['alignment'] = value
         when 'advancement'
            if (['-', '--', 'no', 'none', 'by character class', 'special (see below)'].include?(value))
               next
            elsif (value == '3-5 hd (medium), 6-10 hd (large), or by character class')
               parsed['advancement'] = [
                  '3-5 hd (medium)',
                  '6-10 hd (large)'
               ]
            else
               parsed['advancement'] = value.split('; ').map{|part| part.strip()}
            end
         when 'level_adjustment'
            if (['-', '- (improved familiar)'].include?(value))
               next
            else
               parsed['level_adjustment'] = value
            end
         else
            raise "Unknown statblock header: '#{header}'."
         end
      end
   }

   data[KEY_STATBLOCK] = {
      KEY_RAW => raw,
      KEY_PARSED => parsed
   }
end

def crawlPage(link)
   content = fetchLink(link)
   doc = Nokogiri::HTML(content)

   data = {}
   parseName(doc, data)
   parseStatBlock(doc, data)

   # TODO(eriq): Other data.

   return data
end

def main(monsterLinksPath, outPath)
   monsters = []

   File.open(monsterLinksPath, 'r'){|file|
      file.each{|line|
         line = line.strip()

         if (SKIP_PAGES.include?(line))
            next
         end

         begin
            monster = crawlPage(line)
         rescue Exception => ex
            puts "Failed to create monster [#{line.strip()}]: #{ex}"
            puts ex.backtrace()
            puts '---'

            next
         end

         monsters << monster
      }
   }

   File.open(outPath, 'w'){|file|
      file.puts(JSON.pretty_generate(monsters))
   }
end

def loadArgs(args)
   if (args.size() != 2 || args.map{|arg| arg.gsub('-', '').downcase()}.include?('help'))
      puts "USAGE: ruby #{$0} <monster links> <out path>"
      exit(1)
   end

   inPath = args.shift()
   outPath = args.shift()

   return inPath, outPath
end

if ($0 == __FILE__)
   main(*loadArgs(ARGV))
end
