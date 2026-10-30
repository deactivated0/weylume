import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs

PopupWindow {
    id: root
    required property var anchorItem
    Shortcut { sequence: "Escape"; onActivated: ShellState.closeFlyouts() }

    visible: ShellState.emojiOpen
    implicitWidth: Math.min(430, Math.max(340, (ShellState.popupScreen?.width || 1920) - 8))
    implicitHeight: Math.min(520, Math.max(320, (ShellState.popupScreen?.height || 1080) - Theme.taskbarHeight - 12))
    color: "transparent"
    grabFocus: searchInput.activeFocus
    surfaceFormat.opaque: false
    anchor.item: anchorItem
    anchor.edges: Edges.Top | Edges.Right
    anchor.gravity: Edges.Top | Edges.Left

    property string searchQuery: ""
    property int selectedCategory: 1
    property string hoveredName: ""
    property string lastCopiedChar: ""
    property var recentList: ["😀", "😂", "🥰", "🔥", "👍", "🎉", "❤️", "✨", "🚀", "👏"]

    function clearRecent() {
        root.recentList = [];
        saveRecent();
    }

    function saveRecent() {
        try {
            recentStore.setText(JSON.stringify(root.recentList) + "\n");
        } catch (e) {
            console.warn("Failed to save recent emojis:", e);
        }
    }

    FileView {
        id: recentStore
        path: StateStore.ready ? Quickshell.shellPath("recent_emojis.json") : ""
        onLoaded: {
            try {
                const raw = text();
                if (raw && raw.trim()) {
                    const parsed = JSON.parse(raw);
                    if (Array.isArray(parsed)) root.recentList = parsed;
                }
            } catch (e) {
                console.warn("Failed to load recent emojis:", e);
            }
        }
    }

    Timer {
        id: copiedTimer
        interval: 1400
        onTriggered: root.lastCopiedChar = ""
    }

    onVisibleChanged: {
        if (visible) {
            searchQuery = "";
            hoveredName = "";
            lastCopiedChar = "";
            searchInput.focus = false;
        } else if (ShellState.emojiOpen) {
            ShellState.emojiOpen = false;
        }
    }

    function selectEmoji(em) {
        const char = typeof em === "string" ? em : em.c;
        if (!char) return;

        // Copy to clipboard
        ClipboardService.copy(char);

        // Add to recent list & persist
        let next = [char].concat(root.recentList.filter(c => c !== char)).slice(0, 36);
        root.recentList = next;
        saveRecent();

        root.lastCopiedChar = char;
        copiedTimer.restart();

        // Release focus from search input so wtype targets the user's active window
        if (searchInput.activeFocus) {
            searchInput.focus = false;
        }

        // Type character into active target
        Qt.callLater(() => {
            Quickshell.execDetached(["wtype", char]);
        });
    }

    readonly property var categories: [
        { id: "recent", name: "Recent", icon: "🕒" },
        { id: "smileys", name: "Smileys & Emotion", icon: "😊" },
        { id: "people", name: "People & Body", icon: "👋" },
        { id: "animals", name: "Animals & Nature", icon: "🐶" },
        { id: "food", name: "Food & Drink", icon: "🍔" },
        { id: "travel", name: "Travel & Places", icon: "🚗" },
        { id: "activities", name: "Activities", icon: "⚽" },
        { id: "objects", name: "Objects", icon: "💡" },
        { id: "symbols", name: "Symbols", icon: "🔣" },
        { id: "flags", name: "Flags", icon: "🎌" }
    ]

    readonly property var allEmojis: [
        // Smileys & Emotion
        { c: "😀", n: "Grinning Face", cat: 1, k: "happy smile joy" },
        { c: "😃", n: "Grinning Face with Big Eyes", cat: 1, k: "happy joy" },
        { c: "😄", n: "Grinning Face with Smiling Eyes", cat: 1, k: "happy joy laugh" },
        { c: "😁", n: "Beaming Face with Smiling Eyes", cat: 1, k: "grin smile" },
        { c: "😆", n: "Grinning Squinting Face", cat: 1, k: "laugh haha" },
        { c: "😅", n: "Grinning Face with Sweat", cat: 1, k: "hot relief phew" },
        { c: "🤣", n: "Rolling on the Floor Laughing", cat: 1, k: "rofl lol haha" },
        { c: "😂", n: "Face with Tears of Joy", cat: 1, k: "cry happy funny" },
        { c: "🙂", n: "Slightly Smiling Face", cat: 1, k: "smile" },
        { c: "🙃", n: "Upside-Down Face", cat: 1, k: "sarcasm ironic silly" },
        { c: "😉", n: "Winking Face", cat: 1, k: "wink flirt" },
        { c: "😊", n: "Smiling Face with Smiling Eyes", cat: 1, k: "blush sweet" },
        { c: "😇", n: "Smiling Face with Halo", cat: 1, k: "angel innocent" },
        { c: "🥰", n: "Smiling Face with Hearts", cat: 1, k: "love adore hearts" },
        { c: "😍", n: "Smiling Face with Heart-Eyes", cat: 1, k: "love crush" },
        { c: "🤩", n: "Star-Struck", cat: 1, k: "excited wow stars" },
        { c: "😘", n: "Face Blowing a Kiss", cat: 1, k: "kiss love mwah" },
        { c: "😗", n: "Kissing Face", cat: 1, k: "kiss" },
        { c: "😚", n: "Kissing Face with Closed Eyes", cat: 1, k: "kiss sweet" },
        { c: "😙", n: "Kissing Face with Smiling Eyes", cat: 1, k: "kiss smile" },
        { c: "😋", n: "Face Savoring Food", cat: 1, k: "yum delicious taste" },
        { c: "😛", n: "Face with Tongue", cat: 1, k: "tongue silly" },
        { c: "😜", n: "Winking Face with Tongue", cat: 1, k: "joke wacky crazy" },
        { c: "🤪", n: "Zany Face", cat: 1, k: "crazy wild goofy" },
        { c: "😝", n: "Squinting Face with Tongue", cat: 1, k: "prank tongue" },
        { c: "🤑", n: "Money-Mouth Face", cat: 1, k: "dollar rich cash" },
        { c: "🤗", n: "Smiling Face with Open Hands", cat: 1, k: "hug warm" },
        { c: "🤭", n: "Face with Hand Over Mouth", cat: 1, k: "oops giggle chuckle" },
        { c: "🤫", n: "Shushing Face", cat: 1, k: "quiet silence shh" },
        { c: "🤔", n: "Thinking Face", cat: 1, k: "hmm ponder wonder" },
        { c: "🤐", n: "Zipper-Mouth Face", cat: 1, k: "secret quiet shut" },
        { c: "🤨", n: "Face with Raised Eyebrow", cat: 1, k: "skeptical doubt distrust" },
        { c: "😐", n: "Neutral Face", cat: 1, k: "meh straight okay" },
        { c: "😑", n: "Expressionless Face", cat: 1, k: "blank unresponsive" },
        { c: "😶", n: "Face Without Mouth", cat: 1, k: "mute silent speechless" },
        { c: "😏", n: "Smirking Face", cat: 1, k: "smug sly flirt" },
        { c: "😒", n: "Unamused Face", cat: 1, k: "bored unimpressed annoyed" },
        { c: "🙄", n: "Face with Rolling Eyes", cat: 1, k: "eyeroll whatever sarcastic" },
        { c: "😬", n: "Grimacing Face", cat: 1, k: "awkward cringe nervous" },
        { c: "🤥", n: "Lying Face", cat: 1, k: "pinocchio liar fake" },
        { c: "😌", n: "Relieved Face", cat: 1, k: "calm peace relaxed" },
        { c: "😔", n: "Pensive Face", cat: 1, k: "sad thoughtful regret" },
        { c: "😪", n: "Sleepy Face", cat: 1, k: "tired drip snooze" },
        { c: "🤤", n: "Drooling Face", cat: 1, k: "drool craving hungry" },
        { c: "😴", n: "Sleeping Face", cat: 1, k: "zzz sleep night" },
        { c: "😷", n: "Face with Medical Mask", cat: 1, k: "sick health virus" },
        { c: "🤒", n: "Face with Thermometer", cat: 1, k: "fever sick ill" },
        { c: "🤕", n: "Face with Head-Bandage", cat: 1, k: "hurt pain injury" },
        { c: "🤢", n: "Nauseated Face", cat: 1, k: "gross vomit sick" },
        { c: "🤮", n: "Face Vomiting", cat: 1, k: "puke barf sick" },
        { c: "🤧", n: "Sneezing Face", cat: 1, k: "cold tissue allergy" },
        { c: "🥵", n: "Hot Face", cat: 1, k: "heat sweat summer" },
        { c: "🥶", n: "Cold Face", cat: 1, k: "freezing ice winter" },
        { c: "🥴", n: "Woozy Face", cat: 1, k: "dizzy drunk tipsy" },
        { c: "😵", n: "Face with Crossed-Out Eyes", cat: 1, k: "knockout stunned dead" },
        { c: "🤯", n: "Exploding Head", cat: 1, k: "mind blown shocked" },
        { c: "🤠", n: "Cowboy Hat Face", cat: 1, k: "western hat yeehaw" },
        { c: "🥳", n: "Partying Face", cat: 1, k: "celebrate horn confetti" },
        { c: "😎", n: "Smiling Face with Sunglasses", cat: 1, k: "cool shades swag" },
        { c: "🤓", n: "Nerd Face", cat: 1, k: "glasses geek smart" },
        { c: "🧐", n: "Face with Monocle", cat: 1, k: "curious fancy inspect" },
        { c: "😕", n: "Confused Face", cat: 1, k: "puzzled unsure" },
        { c: "😟", n: "Worried Face", cat: 1, k: "anxious nervous" },
        { c: "🙁", n: "Slightly Frowning Face", cat: 1, k: "sad down" },
        { c: "☹️", n: "Frowning Face", cat: 1, k: "sad upset" },
        { c: "😮", n: "Face with Open Mouth", cat: 1, k: "surprise wow" },
        { c: "😯", n: "Hushed Face", cat: 1, k: "silent stunned" },
        { c: "😲", n: "Astonished Face", cat: 1, k: "shocked amazed" },
        { c: "😳", n: "Flushed Face", cat: 1, k: "embarrassed shy red" },
        { c: "🥺", n: "Pleading Face", cat: 1, k: "begging puppy eyes please" },
        { c: "😦", n: "Frowning Face with Open Mouth", cat: 1, k: "aghast gasp" },
        { c: "😧", n: "Anguished Face", cat: 1, k: "distressed stunned" },
        { c: "😨", n: "Fearful Face", cat: 1, k: "scared fear afraid" },
        { c: "😰", n: "Anxious Face with Sweat", cat: 1, k: "nervous worried sweat" },
        { c: "😥", n: "Sad but Relieved Face", cat: 1, k: "phew close call" },
        { c: "😢", n: "Crying Face", cat: 1, k: "tear sad grief" },
        { c: "😭", n: "Loudly Crying Face", cat: 1, k: "sob tears heartbroken" },
        { c: "😱", n: "Face Screaming in Fear", cat: 1, k: "munch scream terror" },
        { c: "😖", n: "Confounded Face", cat: 1, k: "frustrated overwhelmed" },
        { c: "😣", n: "Persevering Face", cat: 1, k: "struggle endurance" },
        { c: "😞", n: "Disappointed Face", cat: 1, k: "let down sad regret" },
        { c: "😓", n: "Downcast Face with Sweat", cat: 1, k: "defeated sweat sad" },
        { c: "😩", n: "Weary Face", cat: 1, k: "tired exhausted whine" },
        { c: "😫", n: "Tired Face", cat: 1, k: "fatigued done yawn" },
        { c: "🥱", n: "Yawning Face", cat: 1, k: "bored sleepy" },
        { c: "😤", n: "Face with Steam From Nose", cat: 1, k: "triumph huff angry" },
        { c: "😡", n: "Enraged Face", cat: 1, k: "angry rage furious red" },
        { c: "😠", n: "Angry Face", cat: 1, k: "mad cross" },
        { c: "🤬", n: "Face with Symbols on Mouth", cat: 1, k: "swearing cussing furious" },
        { c: "😈", n: "Smiling Face with Horns", cat: 1, k: "devil mischievous evil" },
        { c: "👿", n: "Angry Face with Horns", cat: 1, k: "demon evil mad" },
        { c: "💀", n: "Skull", cat: 1, k: "dead skeleton danger" },
        { c: "☠️", n: "Skull and Crossbones", cat: 1, k: "pirate poison death" },
        { c: "💩", n: "Pile of Poo", cat: 1, k: "poop funny crap" },
        { c: "🤡", n: "Clown Face", cat: 1, k: "circus foolish silly" },
        { c: "👻", n: "Ghost", cat: 1, k: "halloween spooky boo" },
        { c: "👽", n: "Alien", cat: 1, k: "ufo space extraterrestrial" },
        { c: "🤖", n: "Robot", cat: 1, k: "bot ai machine" },
        { c: "❤️", n: "Red Heart", cat: 1, k: "love romantic heart" },
        { c: "🧡", n: "Orange Heart", cat: 1, k: "love warm" },
        { c: "💛", n: "Yellow Heart", cat: 1, k: "friendship love" },
        { c: "💚", n: "Green Heart", cat: 1, k: "nature love envy" },
        { c: "💙", n: "Blue Heart", cat: 1, k: "trust loyalty peace" },
        { c: "💜", n: "Purple Heart", cat: 1, k: "honor respect magic" },
        { c: "🖤", n: "Black Heart", cat: 1, k: "dark grief sorrow" },
        { c: "🤍", n: "White Heart", cat: 1, k: "pure clean peace" },
        { c: "🤎", n: "Brown Heart", cat: 1, k: "chocolate earth" },
        { c: "💔", n: "Broken Heart", cat: 1, k: "breakup sad sorrow" },
        { c: "❤️‍🔥", n: "Heart on Fire", cat: 1, k: "passion desire burning" },
        { c: "✨", n: "Sparkles", cat: 1, k: "magic shiny stars clean" },
        { c: "🔥", n: "Fire", cat: 1, k: "flame hot lit trend" },
        { c: "💯", n: "Hundred Points", cat: 1, k: "perfect 100 score" },

        // People & Body
        { c: "👋", n: "Waving Hand", cat: 2, k: "hello goodbye wave hi" },
        { c: "🤚", n: "Raised Back of Hand", cat: 2, k: "stop hand" },
        { c: "🖐️", n: "Hand with Fingers Splayed", cat: 2, k: "five palm" },
        { c: "✋", n: "Raised Hand", cat: 2, k: "high five stop" },
        { c: "🖖", n: "Vulcan Salute", cat: 2, k: "spock star trek" },
        { c: "👌", n: "OK Hand", cat: 2, k: "perfect fine alright" },
        { c: "🤌", n: "Pinched Fingers", cat: 2, k: "italian gesture what" },
        { c: "🤏", n: "Pinching Hand", cat: 2, k: "small tiny little bit" },
        { c: "✌️", n: "Victory Hand", cat: 2, k: "peace two v sign" },
        { c: "🤞", n: "Crossed Fingers", cat: 2, k: "luck hope wish" },
        { c: "🤟", n: "Love-You Gesture", cat: 2, k: "ily love hand sign" },
        { c: "🤘", n: "Sign of the Horns", cat: 2, k: "rock metal party" },
        { c: "🤙", n: "Call Me Hand", cat: 2, k: "shaka phone hang loose" },
        { c: "👈", n: "Backhand Index Pointing Left", cat: 2, k: "left direction" },
        { c: "👉", n: "Backhand Index Pointing Right", cat: 2, k: "right direction" },
        { c: "👆", n: "Backhand Index Pointing Up", cat: 2, k: "up point look" },
        { c: "👇", n: "Backhand Index Pointing Down", cat: 2, k: "down below look" },
        { c: "☝️", n: "Index Pointing Up", cat: 2, k: "number one attention" },
        { c: "👍", n: "Thumbs Up", cat: 2, k: "like approve good yes" },
        { c: "👎", n: "Thumbs Down", cat: 2, k: "dislike bad no reject" },
        { c: "✊", n: "Raised Fist", cat: 2, k: "solidarity power punch" },
        { c: "👊", n: "Oncoming Fist", cat: 2, k: "fist bump attack" },
        { c: "🤛", n: "Left-Facing Fist", cat: 2, k: "fist bump" },
        { c: "🤜", n: "Right-Facing Fist", cat: 2, k: "fist bump" },
        { c: "👏", n: "Clapping Hands", cat: 2, k: "applause bravo praise" },
        { c: "🙌", n: "Raising Hands", cat: 2, k: "celebrate hooray praise" },
        { c: "👐", n: "Open Hands", cat: 2, k: "open welcome jazz" },
        { c: "🤲", n: "Palms Up Together", cat: 2, k: "prayer offering" },
        { c: "🤝", n: "Handshake", cat: 2, k: "deal agreement meet" },
        { c: "🙏", n: "Folded Hands", cat: 2, k: "pray please thank you namaste" },
        { c: "💪", n: "Flexed Biceps", cat: 2, k: "strong muscle power gym" },
        { c: "🧠", n: "Brain", cat: 2, k: "smart mind think intelligence" },
        { c: "👀", n: "Eyes", cat: 2, k: "look see watch stare" },
        { c: "👁️", n: "Eye", cat: 2, k: "vision sight" },
        { c: "👅", n: "Tongue", cat: 2, k: "taste lick mouth" },
        { c: "👄", n: "Mouth", cat: 2, k: "lips kiss speak" },

        // Animals & Nature
        { c: "🐶", n: "Dog Face", cat: 3, k: "puppy pet canine" },
        { c: "🐱", n: "Cat Face", cat: 3, k: "kitten pet feline meow" },
        { c: "🐭", n: "Mouse Face", cat: 3, k: "rodent cheese" },
        { c: "🐹", n: "Hamster", cat: 3, k: "pet cute rodent" },
        { c: "🐰", n: "Rabbit Face", cat: 3, k: "bunny easter cute" },
        { c: "🦊", n: "Fox", cat: 3, k: "clever sly animal" },
        { c: "🐻", n: "Bear", cat: 3, k: "grizzly animal wild" },
        { c: "🐼", n: "Panda", cat: 3, k: "bear bamboo china" },
        { c: "🐨", n: "Koala", cat: 3, k: "australia animal" },
        { c: "🐯", n: "Tiger Face", cat: 3, k: "cat wild roar" },
        { c: "🦁", n: "Lion", cat: 3, k: "king roar pride" },
        { c: "🐮", n: "Cow Face", cat: 3, k: "beef milk moo" },
        { c: "🐷", n: "Pig Face", cat: 3, k: "oink pork farm" },
        { c: "🐸", n: "Frog", cat: 3, k: "toad amphibian ribbit" },
        { c: "🐵", n: "Monkey Face", cat: 3, k: "primate banana" },
        { c: "🐔", n: "Chicken", cat: 3, k: "rooster bird farm" },
        { c: "🐧", n: "Penguin", cat: 3, k: "bird antarctic linux tux" },
        { c: "🐦", n: "Bird", cat: 3, k: "fly feathers tweet" },
        { c: "🦆", n: "Duck", cat: 3, k: "quack bird pond" },
        { c: "🦅", n: "Eagle", cat: 3, k: "bird prey raptor usa" },
        { c: "🦉", n: "Owl", cat: 3, k: "wise night nocturnal" },
        { c: "🦇", n: "Bat", cat: 3, k: "vampire cave night" },
        { c: "🐺", n: "Wolf", cat: 3, k: "howl pack wild" },
        { c: "🐗", n: "Boar", cat: 3, k: "pig wild tusks" },
        { c: "🐴", n: "Horse Face", cat: 3, k: "steed equestrian ride" },
        { c: "🦄", n: "Unicorn", cat: 3, k: "magic fantasy rainbow" },
        { c: "🐝", n: "Honeybee", cat: 3, k: "bee honey insect buzz" },
        { c: "🦋", n: "Butterfly", cat: 3, k: "insect wings pretty" },
        { c: "🐌", n: "Snail", cat: 3, k: "slow shell slime" },
        { c: "🐢", n: "Turtle", cat: 3, k: "tortoise slow shell" },
        { c: "🐍", n: "Snake", cat: 3, k: "serpent reptile python" },
        { c: "🐙", n: "Octopus", cat: 3, k: "tentacles ocean sea" },
        { c: "🐬", n: "Dolphin", cat: 3, k: "sea ocean smart" },
        { c: "🐳", n: "Spouting Whale", cat: 3, k: "ocean ocean ocean sea" },
        { c: "🦈", n: "Shark", cat: 3, k: "predator jaws ocean" },
        { c: "🌲", n: "Evergreen Tree", cat: 3, k: "pine forest nature" },
        { c: "🌸", n: "Cherry Blossom", cat: 3, k: "flower sakura spring pink" },
        { c: "🌹", n: "Rose", cat: 3, k: "flower red love" },
        { c: "🌻", n: "Sunflower", cat: 3, k: "flower yellow sun" },
        { c: "🍀", n: "Four Leaf Clover", cat: 3, k: "luck irish st patrick" },

        // Food & Drink
        { c: "🍏", n: "Green Apple", cat: 4, k: "fruit healthy" },
        { c: "🍎", n: "Red Apple", cat: 4, k: "fruit teacher" },
        { c: "🍌", n: "Banana", cat: 4, k: "fruit yellow monkey" },
        { c: "🍉", n: "Watermelon", cat: 4, k: "fruit summer melon" },
        { c: "🍇", n: "Grapes", cat: 4, k: "fruit wine purple" },
        { c: "🍓", n: "Strawberry", cat: 4, k: "fruit berry red" },
        { c: "🍒", n: "Cherries", cat: 4, k: "fruit sweet pair" },
        { c: "🍑", n: "Peach", cat: 4, k: "fruit sweet butt" },
        { c: "🍍", n: "Pineapple", cat: 4, k: "tropical fruit sweet" },
        { c: "🥑", n: "Avocado", cat: 4, k: "guacamole healthy" },
        { c: "🍔", n: "Hamburger", cat: 4, k: "burger fast food beef" },
        { c: "🍟", n: "French Fries", cat: 4, k: "chips potato fast food" },
        { c: "🍕", n: "Pizza", cat: 4, k: "cheese italian slice" },
        { c: "🌭", n: "Hot Dog", cat: 4, k: "sausage bun fast food" },
        { c: "🥪", n: "Sandwich", cat: 4, k: "bread lunch" },
        { c: "🌮", n: "Taco", cat: 4, k: "mexican tortilla" },
        { c: "🌯", n: "Burrito", cat: 4, k: "wrap mexican" },
        { c: "🍜", n: "Steaming Bowl", cat: 4, k: "noodles ramen soup" },
        { c: "🍝", n: "Spaghetti", cat: 4, k: "pasta italian sauce" },
        { c: "🍣", n: "Sushi", cat: 4, k: "japanese fish rice" },
        { c: "🍦", n: "Soft Ice Cream", cat: 4, k: "dessert dairy cone" },
        { c: "🍰", n: "Shortcake", cat: 4, k: "cake dessert sweet" },
        { c: "🎂", n: "Birthday Cake", cat: 4, k: "celebrate birthday candles" },
        { c: "🍩", n: "Doughnut", cat: 4, k: "donut dessert sweet glaze" },
        { c: "🍪", n: "Cookie", cat: 4, k: "biscuit chocolate chip sweet" },
        { c: "🍫", n: "Chocolate Bar", cat: 4, k: "candy sweet cocoa" },
        { c: "🍿", n: "Popcorn", cat: 4, k: "movie theater snack" },
        { c: "☕", n: "Hot Beverage", cat: 4, k: "coffee tea caffeine drink" },
        { c: "🍵", n: "Teacup Without Handle", cat: 4, k: "green tea matcha" },
        { c: "🍺", n: "Beer Mug", cat: 4, k: "alcohol drink pub" },
        { c: "🍻", n: "Clinking Beer Mugs", cat: 4, k: "cheers alcohol toast" },
        { c: "🍷", n: "Wine Glass", cat: 4, k: "red wine alcohol drink" },
        { c: "🥂", n: "Clinking Glasses", cat: 4, k: "champagne toast celebrate" },

        // Travel & Places
        { c: "🚗", n: "Automobile", cat: 5, k: "car vehicle drive" },
        { c: "🚕", n: "Taxi", cat: 5, k: "cab car ride" },
        { c: "🚙", n: "Sport Utility Vehicle", cat: 5, k: "suv car travel" },
        { c: "🚌", n: "Bus", cat: 5, k: "transit school transit" },
        { c: "🏎️", n: "Racing Car", cat: 5, k: "f1 race motorsport fast" },
        { c: "🚓", n: "Police Car", cat: 5, k: "cop emergency law" },
        { c: "🚑", n: "Ambulance", cat: 5, k: "emergency medical hospital" },
        { c: "🚒", n: "Fire Engine", cat: 5, k: "truck fire firefighter" },
        { c: "🚲", n: "Bicycle", cat: 5, k: "bike cycle pedal exercise" },
        { c: "🛵", n: "Motor Scooter", cat: 5, k: "vespa transport" },
        { c: "🏍️", n: "Motorcycle", cat: 5, k: "motorbike bike speed" },
        { c: "✈️", n: "Airplane", cat: 5, k: "flight fly travel airport" },
        { c: "🚀", n: "Rocket", cat: 5, k: "space launch blast off moon" },
        { c: "🛸", n: "Flying Saucer", cat: 5, k: "ufo alien space" },
        { c: "🚢", n: "Ship", cat: 5, k: "cruise boat ocean water" },
        { c: "🚆", n: "Train", cat: 5, k: "railway railway commute locomotive" },
        { c: "🏠", n: "House", cat: 5, k: "home building residence" },
        { c: "🏢", n: "Office Building", cat: 5, k: "work company city" },
        { c: "🏰", n: "Castle", cat: 5, k: "fairy palace kingdom" },
        { c: "🌋", n: "Volcano", cat: 5, k: "lava eruption mountain" },

        // Activities
        { c: "⚽", n: "Soccer Ball", cat: 6, k: "football sport kick" },
        { c: "🏀", n: "Basketball", cat: 6, k: "sport hoop dribble" },
        { c: "🏈", n: "American Football", cat: 6, k: "superbowl nfl sport" },
        { c: "⚾", n: "Baseball", cat: 6, k: "sport bat pitch mlb" },
        { c: "🎾", n: "Tennis", cat: 6, k: "racket court sport match" },
        { c: "🏐", n: "Volleyball", cat: 6, k: "beach court sport" },
        { c: "🎱", n: "Pool 8 Ball", cat: 6, k: "billiards game eight" },
        { c: "🏓", n: "Ping Pong", cat: 6, k: "table tennis paddle" },
        { c: "🥊", n: "Boxing Glove", cat: 6, k: "fight punch glove" },
        { c: "🎯", n: "Bullseye", cat: 6, k: "target dart aim goal" },
        { c: "🎮", n: "Video Game", cat: 6, k: "controller gaming play console" },
        { c: "🎲", n: "Game Die", cat: 6, k: "dice roll board game luck" },
        { c: "♟️", n: "Chess Pawn", cat: 6, k: "game strategy checkmate" },
        { c: "🏆", n: "Trophy", cat: 6, k: "prize winner champion gold" },
        { c: "🥇", n: "1st Place Medal", cat: 6, k: "first winner gold" },
        { c: "🥈", n: "2nd Place Medal", cat: 6, k: "second silver" },
        { c: "🥉", n: "3rd Place Medal", cat: 6, k: "third bronze" },
        { c: "🎉", n: "Party Popper", cat: 6, k: "tada celebrate congratulations" },
        { c: "🎨", n: "Artist Palette", cat: 6, k: "art paint color drawing" },
        { c: "🎬", n: "Clapper Board", cat: 6, k: "movie film cinema cut" },

        // Objects
        { c: "📱", n: "Mobile Phone", cat: 7, k: "cell smartphone iphone android" },
        { c: "💻", n: "Laptop", cat: 7, k: "computer pc notebook mac" },
        { c: "🖥️", n: "Desktop Computer", cat: 7, k: "pc monitor screen display" },
        { c: "⌨️", n: "Keyboard", cat: 7, k: "type keys input" },
        { c: "🖱️", n: "Computer Mouse", cat: 7, k: "click pointer device" },
        { c: "📷", n: "Camera", cat: 7, k: "photo picture snapshot" },
        { c: "💡", n: "Light Bulb", cat: 7, k: "idea bright electric genius" },
        { c: "🔦", n: "Flashlight", cat: 7, k: "torch light beam" },
        { c: "📖", n: "Open Book", cat: 7, k: "read study literature novel" },
        { c: "💰", n: "Money Bag", cat: 7, k: "dollar rich wealth gold" },
        { c: "💳", n: "Credit Card", cat: 7, k: "payment bank money debit" },
        { c: "💎", n: "Gem Stone", cat: 7, k: "diamond precious jewel rich" },
        { c: "🔧", n: "Wrench", cat: 7, k: "tool spanner repair fix" },
        { c: "🔨", n: "Hammer", cat: 7, k: "tool nail build" },
        { c: "⚙️", n: "Gear", cat: 7, k: "settings cog options mechanical" },
        { c: "🔒", n: "Locked", cat: 7, k: "padlock secure safety privacy" },
        { c: "🔓", n: "Unlocked", cat: 7, k: "padlock open access" },
        { c: "🔑", n: "Key", cat: 7, k: "lock password secret unlock" },
        { c: "📦", n: "Package", cat: 7, k: "box delivery shipping parcel" },
        { c: "🎁", n: "Wrapped Gift", cat: 7, k: "present birthday christmas box" },

        // Symbols
        { c: "✅", n: "Check Mark Button", cat: 8, k: "yes ok done approve" },
        { c: "❌", n: "Cross Mark", cat: 8, k: "no wrong cancel bad delete" },
        { c: "⚠️", n: "Warning", cat: 8, k: "caution alert hazard danger" },
        { c: "⛔", n: "No Entry", cat: 8, k: "stop forbidden restricted" },
        { c: "🚫", n: "Prohibited", cat: 8, k: "no ban disallowed" },
        { c: "ℹ️", n: "Information", cat: 8, k: "info help details" },
        { c: "❓", n: "Question Mark", cat: 8, k: "help query what" },
        { c: "❗", n: "Exclamation Mark", cat: 8, k: "important attention alert" },
        { c: "⭐", n: "Star", cat: 8, k: "favorite rating yellow" },
        { c: "🌟", n: "Glowing Star", cat: 8, k: "sparkle special glitter" },
        { c: "🎵", n: "Musical Note", cat: 8, k: "song melody audio music" },
        { c: "🎶", n: "Musical Notes", cat: 8, k: "music tune audio" },
        { c: "💬", n: "Speech Balloon", cat: 8, k: "chat comment message talk" },
        { c: "💭", n: "Thought Balloon", cat: 8, k: "dream thinking cloud" },
        { c: "🔄", n: "Counterclockwise Arrows", cat: 8, k: "refresh reload sync rotate" },
        { c: "⚡", n: "High Voltage", cat: 8, k: "lightning electric power energy" },

        // Flags
        { c: "🏁", n: "Chequered Flag", cat: 9, k: "finish race victory end" },
        { c: "🚩", n: "Triangular Flag", cat: 9, k: "red flag mark post" },
        { c: "🏳️", n: "White Flag", cat: 9, k: "surrender peace truce" },
        { c: "🏴", n: "Black Flag", cat: 9, k: "pirate flag" },
        { c: "🏳️‍🌈", n: "Rainbow Flag", cat: 9, k: "pride lgbt equality" },
        { c: "🏳️‍⚧️", n: "Transgender Flag", cat: 9, k: "transgender pride" },
        { c: "🇺🇸", n: "Flag: United States", cat: 9, k: "usa america american" },
        { c: "🇬🇧", n: "Flag: United Kingdom", cat: 9, k: "uk britain british england" },
        { c: "🇩🇪", n: "Flag: Germany", cat: 9, k: "germany deutschland german" },
        { c: "🇫🇷", n: "Flag: France", cat: 9, k: "france french" },
        { c: "🇯🇵", n: "Flag: Japan", cat: 9, k: "japan japanese tokyo" },
        { c: "🇨🇳", n: "Flag: China", cat: 9, k: "china chinese" },
        { c: "🇨🇦", n: "Flag: Canada", cat: 9, k: "canada canadian" },
        { c: "🇧🇷", n: "Flag: Brazil", cat: 9, k: "brazil brazilian" },
        { c: "🇦🇺", n: "Flag: Australia", cat: 9, k: "australia aussie" },
        { c: "🇮🇳", n: "Flag: India", cat: 9, k: "india indian" }
    ]

    readonly property var currentList: {
        const q = root.searchQuery.trim().toLowerCase();
        if (q.length > 0) {
            return allEmojis.filter(e => e.n.toLowerCase().includes(q) || e.k.toLowerCase().includes(q));
        }
        if (selectedCategory === 0) {
            return recentList.map(c => {
                const found = allEmojis.find(e => e.c === c);
                return found || { c: c, n: "Recent", cat: 0, k: "" };
            });
        }
        return allEmojis.filter(e => e.cat === selectedCategory);
    }

    Rectangle {
        id: container
        anchors.fill: parent
        anchors.margins: 4
        radius: 16
        color: Theme.background
        border.width: 1
        border.color: Theme.border
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            // iOS-style Search Top Bar
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    height: 34
                    radius: 10
                    color: "#121212"
                    border.width: 1
                    border.color: searchInput.activeFocus ? "#3a3a3c" : "#1a1a1a"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 7

                        Text {
                            text: "🔍"
                            font.pixelSize: 11
                            color: "#8e8e93"
                        }

                        TextInput {
                            id: searchInput
                            Layout.fillWidth: true
                            color: "#ffffff"
                            font.family: Theme.fontFamily
                            font.pixelSize: 12
                            selectByMouse: true
                            onTextChanged: root.searchQuery = text

                            Text {
                                anchors.fill: parent
                                visible: searchInput.text.length === 0
                                text: "Search Emoji"
                                color: "#636366"
                                font.family: Theme.fontFamily
                                font.pixelSize: 12
                            }
                        }

                        Rectangle {
                            visible: searchInput.text.length > 0
                            width: 18
                            height: 18
                            radius: 9
                            color: clearMouse.containsMouse ? "#2c2c2e" : "#1c1c1e"
                            Text { anchors.centerIn: parent; text: "✕"; color: "#aeaeb2"; font.pixelSize: 9 }
                            MouseArea {
                                id: clearMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    searchInput.text = "";
                                    searchInput.forceActiveFocus();
                                }
                            }
                        }
                    }
                }

                // iOS-style Close Button
                Rectangle {
                    width: 30
                    height: 30
                    radius: 15
                    color: closeMouse.containsMouse ? "#2c2c2e" : "#141414"
                    border.width: 1
                    border.color: closeMouse.containsMouse ? "#3a3a3c" : "#1c1c1c"
                    Text { anchors.centerIn: parent; text: "✕"; color: "#aeaeb2"; font.pixelSize: 11 }
                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ShellState.closeFlyouts()
                    }
                }
            }

            // iOS-style Segmented Category Dock
            Rectangle {
                Layout.fillWidth: true
                height: 36
                color: "#0a0a0a"
                radius: 10
                border.width: 1
                border.color: "#161616"

                Flickable {
                    id: catFlick
                    anchors.fill: parent
                    contentWidth: catRow.implicitWidth + 8
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    RowLayout {
                        id: catRow
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        spacing: 3

                        Repeater {
                            model: root.categories
                            Rectangle {
                                id: catBtn
                                required property var modelData
                                required property int index
                                width: 38
                                height: 28
                                radius: 8
                                color: root.selectedCategory === catBtn.index ? "#2c2c2e" : (catMouse.containsMouse ? "#1c1c1e" : "transparent")
                                border.width: root.selectedCategory === catBtn.index ? 1 : 0
                                border.color: "#3a3a3c"

                                Behavior on color { ColorAnimation { duration: SettingsService.reducedMotion ? 0 : 80 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: catBtn.modelData.icon
                                    font.pixelSize: 16
                                    opacity: root.selectedCategory === catBtn.index ? 1.0 : 0.65
                                }

                                MouseArea {
                                    id: catMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.searchQuery = "";
                                        searchInput.text = "";
                                        root.selectedCategory = catBtn.index;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // AMOLED Pure Black Emoji Grid View
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "#000000"
                radius: 10
                border.width: 1
                border.color: "#141414"
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    // Recent header bar with Clear Recent button
                    Rectangle {
                        visible: root.selectedCategory === 0 && !root.searchQuery
                        Layout.fillWidth: true
                        height: 32
                        color: "#050505"
                        border.width: 1
                        border.color: "#111111"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10

                            Text {
                                text: "RECENTLY USED"
                                color: "#8e8e93"
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }

                            Item { Layout.fillWidth: true }

                            Rectangle {
                                visible: root.recentList.length > 0
                                implicitWidth: clearRecentRow.implicitWidth + 14
                                implicitHeight: 22
                                radius: 11
                                color: clearRecentMouse.containsMouse ? "#2c2c2e" : "#141414"
                                border.width: 1
                                border.color: clearRecentMouse.containsMouse ? "#ff453a" : "#222222"

                                RowLayout {
                                    id: clearRecentRow
                                    anchors.centerIn: parent
                                    spacing: 4

                                    Text {
                                        text: "🗑"
                                        font.pixelSize: 10
                                    }

                                    Text {
                                        text: "Clear Recent"
                                        color: clearRecentMouse.containsMouse ? "#ff453a" : "#aeaeb2"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 10
                                        font.weight: Font.Medium
                                    }
                                }

                                MouseArea {
                                    id: clearRecentMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.clearRecent()
                                }
                            }
                        }
                    }

                    ScrollView {
                        id: scroll
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.margins: 4
                        contentWidth: availableWidth
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        ScrollBar.vertical.policy: ScrollBar.AsNeeded

                        Flow {
                            id: flowGrid
                            width: scroll.availableWidth
                            spacing: 4

                            Repeater {
                                model: root.currentList
                                Rectangle {
                                    id: emCell
                                    required property var modelData
                                    width: Math.floor((flowGrid.width - 25) / 6)
                                    height: width
                                    radius: 10
                                    color: emMouse.pressed ? "#2c2c2e" : (emMouse.containsMouse ? "#1c1c1e" : "transparent")
                                    border.width: emMouse.containsMouse ? 1 : 0
                                    border.color: "#2c2c2e"

                                    Behavior on color { ColorAnimation { duration: SettingsService.reducedMotion ? 0 : 50 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: emCell.modelData.c
                                        font.pixelSize: Math.max(26, Math.floor(emCell.width * 0.58))
                                    }

                                    MouseArea {
                                        id: emMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: root.hoveredName = emCell.modelData.n || ""
                                        onExited: if (root.hoveredName === (emCell.modelData.n || "")) root.hoveredName = ""
                                        onClicked: {
                                            searchInput.focus = false;
                                            root.selectEmoji(emCell.modelData);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: root.currentList.length === 0
                    text: root.selectedCategory === 0 ? "No recent emojis\nClick any emoji to add here" : "No emojis found"
                    horizontalAlignment: Text.AlignHCenter
                    lineHeight: 1.3
                    color: "#636366"
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
            }

            // iOS-style Footer Status Bar
            Rectangle {
                Layout.fillWidth: true
                height: 20
                color: "transparent"

                RowLayout {
                    anchors.fill: parent
                    spacing: 6

                    Text {
                        Layout.fillWidth: true
                        text: root.lastCopiedChar ? ("Copied " + root.lastCopiedChar + " to clipboard") : (root.hoveredName.length > 0 ? root.hoveredName : "Click to copy & insert • Win + . to toggle")
                        color: root.lastCopiedChar ? "#30d158" : (root.hoveredName.length > 0 ? "#ffffff" : "#636366")
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.weight: (root.lastCopiedChar || root.hoveredName.length > 0) ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
