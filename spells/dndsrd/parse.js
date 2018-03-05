// Run this on a page like: http://dndsrd.net/spellsAtoB.html#acid-arrow

var STATE_OPEN = 0;
var STATE_SCHOOL = 1;
var STATE_SPELLBLOCK = 2;
var STATE_DESCRIPTION = 3;

function parseSchool(text, spell) {
   parts = text.replace(/\s+/g, '').match(/^([^(\[]+)(?:\(([^\[]+)\))?(?:\[(.+)\])?$/);
   if (!parts) {
      throw "Bad school regex: '" + text + "'.";
   }

   if (!parts[1]) {
      throw "Cannot parse school: '" + text + "'.";
   }

   spell['school'] = parts[1]

   if (parts[2]) {
      spell['subschool'] = parts[2];
   }

   if (parts[3]) {
      descriptors = [];
      parts[3].split(',').forEach(function(part) {
         if (part != 'seetext') {
            descriptors.push(part);
         }
      });

      if (descriptors.length > 0) {
         spell['descriptors'] = descriptors;
      }
   }
}

function cleanText(text) {
   return text.replace(/’/g, "'");
}

function parseSpells() {
   var state = STATE_OPEN;
   var spells = [];
   var spell = null;

   var nodes = document.querySelector('body table tbody tr:nth-child(3) td:nth-child(3)').children;
   for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i];
      
      if (state == STATE_OPEN) {
         if (node.tagName != 'H6') {
            continue;
         }
         
         name = cleanText(node.textContent);

         // Skip special non-spell entries.
         if (name == 'Greater (Spell Name)' || name == 'Lesser (Spell Name)' || name == 'Mass (Spell Name)') {
            continue;
         }

         spell = {'name': name};
         state = STATE_SCHOOL;
      } else if (state == STATE_SCHOOL) {
         if (node.tagName != 'P') {
            continue;
         }

         parseSchool(node.textContent, spell);
         state = STATE_SPELLBLOCK;
      } else if (state == STATE_SPELLBLOCK) {
         if (node.tagName == 'P') {
            // If we are ready to move onto the description, then roll back one.
            i--;
            state = STATE_DESCRIPTION;
            continue;
         }

         // Sometimes empty block rows come up.
         if (!node.textContent) {
            continue;
         }

         content = node.textContent;

         // Sometimes nodes some up that are not classed correctly and have the actual data in the next node.
         if (node.className != 'stat-block') {
            content += " " + node.nextSibling.textContent;
         }

         match = content.match(/^([^:]+)\s*:\s*(.+)$/);
         if (!match) {
            throw "Bad spellblock row: '" + content + "' (" + spell['name'] + ").";
         }

         key = match[1].trim().toLowerCase().replace(/ /g, '_');
         value = match[2].trim();

         spell[key] = value;
      } else if (state == STATE_DESCRIPTION) {
         if (node.tagName == 'H6') {
            i--;
            state = STATE_OPEN;
            spells.push(spell);
            continue;
         }
         
         if (node.tagName == 'TABLE') {
            if (!('additional_tables' in spell)) {
               spell['additional_tables'] = [];
            }

            spell['additional_tables'].push(node.innerHTML);
            continue;
         }

         if (!('description' in spell)) {
            spell['description'] = [];
         }

         spell['description'].push(cleanText(node.textContent));
      } else {
         throw "Bad state: [" + state + "].";
      }
   }

   return spells;
}

var spells = parseSpells();
console.log(JSON.stringify(spells, null, 3));
