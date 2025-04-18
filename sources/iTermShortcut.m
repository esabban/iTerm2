//
//  iTermShortcut.m
//  iTerm2
//
//  Created by George Nachman on 6/27/16.
//
//

#import "iTermShortcut.h"

#import "iTermCarbonHotKeyController.h"
#import "iTermKeystroke.h"
#import "iTermKeystrokeFormatter.h"
#import "iTermProfilePreferences.h"
#import "NSArray+iTerm.h"
#import "NSEvent+iTerm.h"
#import "NSStringITerm.h"

// IMPORTANT: When adding to this list also update the short string class methods.
static NSString *const kKeyCode = @"keyCode";
static NSString *const kModifiers = @"modifiers";
static NSString *const kCharacters = @"characters";
static NSString *const kCharactersIgnoringModifiers = @"charactersIgnoringModifiers";

// Only append to this string! Its indexes count. Never make it longer than 10 characters. backslash -> \0, comma -> \1, space -> \2.
static NSString *sCharsToEscape = @"\\, ";

CGFloat kShortcutPreferredHeight = 22;

// The numeric keypad mask is here so we can disambiguate between keys that
// exist in both the numeric keypad and outside of it.
const NSEventModifierFlags kHotKeyModifierMask = (NSEventModifierFlagCommand |
                                                  NSEventModifierFlagOption |
                                                  NSEventModifierFlagShift |
                                                  NSEventModifierFlagControl |
                                                  iTermLeaderModifierFlag |
                                                  NSEventModifierFlagNumericPad);

@implementation iTermShortcut {
    NSEventModifierFlags _modifiers;
}

+ (NSString *)escapedString:(NSString *)input {
    NSString *escaped = input;
    for (NSUInteger i = 0; i < sCharsToEscape.length; i++) {
        NSString *replacement = [NSString stringWithFormat:@"\\%d", (int)i];
        escaped = [escaped stringByReplacingOccurrencesOfString:[sCharsToEscape substringWithRange:NSMakeRange(i, 1)]
                                                     withString:replacement];
    }
    return escaped;
}

+ (NSString *)shortStringForDictionary:(NSDictionary *)dict {
    return [NSString stringWithFormat:@"%@,%@,%@,%@", dict[kKeyCode], dict[kModifiers], [self escapedString:dict[kCharacters]], [self escapedString:dict[kCharactersIgnoringModifiers]]];
}

+ (NSDictionary *)dictionaryForShortString:(NSString *)string {
    NSMutableString *temp = [NSMutableString string];
    NSMutableArray *parts = [NSMutableArray array];
    BOOL esc = NO;
    for (int i = 0; i < string.length; i++) {
        unichar c = [string characterAtIndex:i];
        if (esc) {
            int j = (int)c - '0';
            if (j >= 0 && j < sCharsToEscape.length) {
                [temp appendCharacter:[sCharsToEscape characterAtIndex:j]];
            }
            esc = NO;
        } else if (c == '\\') {
            esc = YES;
        } else if (c == ',') {
            [parts addObject:temp];
            temp = [NSMutableString string];
        } else {
            [temp appendCharacter:c];
        }
    }
    [parts addObject:temp];
    if (parts.count < 4) {
        return nil;
    }
    return @{ kKeyCode: @([parts[0] iterm_unsignedIntegerValue]),
              kModifiers: @([parts[1] iterm_unsignedIntegerValue]),
              kCharacters: parts[2],
              kCharactersIgnoringModifiers: parts[3] };
}

+ (NSArray<iTermShortcut *> *)shortcutsForProfile:(Profile *)profile {
    iTermShortcut *main = [[iTermShortcut alloc] init];
    main.keyCode = [iTermProfilePreferences unsignedIntegerForKey:KEY_HOTKEY_KEY_CODE inProfile:profile];
    main.modifiers = [iTermProfilePreferences unsignedIntegerForKey:KEY_HOTKEY_MODIFIER_FLAGS inProfile:profile];
    main.characters = [iTermProfilePreferences stringForKey:KEY_HOTKEY_CHARACTERS inProfile:profile];
    main.charactersIgnoringModifiers = [iTermProfilePreferences stringForKey:KEY_HOTKEY_CHARACTERS_IGNORING_MODIFIERS inProfile:profile];

    NSMutableArray *result =[NSMutableArray array];
    [result addObject:main];
    NSArray<NSDictionary *> *additional = (NSArray *)[profile objectForKey:KEY_HOTKEY_ALTERNATE_SHORTCUTS];
    [result addObjectsFromArray:[additional mapWithBlock:^id(NSDictionary *anObject) {
        return [self shortcutWithDictionary:anObject];
    }]];
    return [result filteredArrayUsingBlock:^BOOL(iTermShortcut *anObject) {
        return anObject.isAssigned;
    }];
}

+ (instancetype)shortcutWithDictionary:(NSDictionary *)dictionary {
    // Empty dict is the default for a profile; can't specify nil default because objc.
    if (!dictionary || !dictionary.count) {
        return nil;
    }
    iTermShortcut *shortcut = [[iTermShortcut alloc] init];
    shortcut.keyCode = [dictionary[kKeyCode] unsignedIntegerValue];
    shortcut.modifiers = [dictionary[kModifiers] unsignedIntegerValue];
    shortcut.characters = dictionary[kCharacters];
    shortcut.charactersIgnoringModifiers = dictionary[kCharactersIgnoringModifiers];
    return shortcut;
}

+ (instancetype)shortcutWithEvent:(NSEvent *)event
                    leaderAllowed:(BOOL)leaderAllowed {
    NSEventModifierFlags flags = event.it_modifierFlags;
    if (!leaderAllowed) {
        flags &= ~iTermLeaderModifierFlag;
    }
    return [[self alloc] initWithKeyCode:event.keyCode
                              hasKeyCode:YES
                               modifiers:flags
                              characters:event.characters
             charactersIgnoringModifiers:event.charactersIgnoringModifiers];
}

+ (instancetype)shortcutWithEvent:(NSEvent *)event {
    return [self shortcutWithEvent:event leaderAllowed:YES];
}

- (instancetype)init {
    return [self initWithKeyCode:0 hasKeyCode:NO modifiers:0 characters:@"" charactersIgnoringModifiers:@""];
}

- (instancetype)initWithKeyCode:(NSUInteger)code
                     hasKeyCode:(BOOL)hasKeyCode
                      modifiers:(NSEventModifierFlags)modifiers
                     characters:(NSString *)characters
    charactersIgnoringModifiers:(NSString *)charactersIgnoringModifiers {
    self = [super init];
    if (self) {
        _keyCode = code;
        _hasKeyCode = hasKeyCode;
        _modifiers = modifiers & kHotKeyModifierMask;
        _characters = [characters copy];
        _charactersIgnoringModifiers = [charactersIgnoringModifiers copy];
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p keyCode=%@ modifiers=%@ (%@) characters=“%@” (0x%@) charactersIgnoringModifiers=“%@” (0x%@)>",
            NSStringFromClass([self class]), self, @(self.keyCode), @(self.modifiers),
            [NSString stringForModifiersWithMask:self.modifiers], self.characters, [self.characters hexEncodedString],
            self.charactersIgnoringModifiers, [self.charactersIgnoringModifiers hexEncodedString]];
}

- (BOOL)isEqual:(id)object {
    if ([object isKindOfClass:[iTermShortcut class]]) {
        return [self isEqualToShortcut:object];
    } else {
        return NO;
    }
}

- (BOOL)isEqualToShortcut:(iTermShortcut *)object {
    return (object.keyCode == self.keyCode &&
            object.modifiers == self.modifiers &&
            [object.characters isEqual:self.characters] &&
            [object.charactersIgnoringModifiers isEqual:self.charactersIgnoringModifiers]);
}

- (NSUInteger)hash {
    NSArray *components = @[ @(self.keyCode),
                             @(self.modifiers),
                             self.characters ?: @"",
                             self.charactersIgnoringModifiers ?: @"" ];
    return [components hashWithDJB2];
}

#pragma mark - Accessors

- (NSDictionary *)dictionaryValue {
    return @{ kKeyCode: @(self.keyCode),
              kModifiers: @(self.modifiers),
              kCharacters: self.characters ?: @"",
              kCharactersIgnoringModifiers: self.charactersIgnoringModifiers ?: @"" };
}

- (iTermKeystroke *)keystroke {
    return [[iTermKeystroke alloc] initWithVirtualKeyCode:self.keyCode
                                               hasKeyCode:self.hasKeyCode
                                            modifierFlags:self.modifiers
                                                character:[self.charactersIgnoringModifiers firstCharacter]
                                        modifiedCharacter:[self.characters firstCharacter]];
}

- (NSString *)stringValue {
    // Dead keys can have characters without charactersIgnoringModifiers. For example, option+` on
    // a German keyboard enters an apostrophe ('). The ` key is a dead key, so if you ignore modifiers
    // it's nothing. So if there are either characters or characters ignoring modifiers, it's a
    // formattable shortcut. If you press just the dead key then both characters and charactersIgnoringModifiers
    // will be empty.
    const BOOL valid = (self.charactersIgnoringModifiers.length > 0 ||
                        self.characters.length > 0 ||
                        self.keyCode != 0);
    return valid ? [iTermKeystrokeFormatter stringForKeystroke:self.keystroke] : @"";
}

- (BOOL)isAssigned {
    return self.charactersIgnoringModifiers.length > 0 || self.characters.length > 0 || self.keyCode != 0;
}

- (iTermHotKeyDescriptor *)descriptor {
    return _charactersIgnoringModifiers.length > 0 ? [NSDictionary descriptorWithKeyCode:self.keyCode modifiers:self.modifiers] : nil;
}

- (void)setModifiers:(NSEventModifierFlags)modifiers {
    _modifiers = (modifiers & kHotKeyModifierMask);
}

- (NSEventModifierFlags)modifiers {
    // On some keyboards, arrow keys have NSEventModifierFlagNumericPad bit set; manually set it for keyboards that don't.
    if (self.keyCode >= NSUpArrowFunctionKey && self.keyCode <= NSRightArrowFunctionKey) {
        return _modifiers | NSEventModifierFlagNumericPad;
    } else {
        return _modifiers;
    }
}

#pragma mark - APIs

- (void)setFromEvent:(NSEvent *)event {
    self.keyCode = event.keyCode;
    self.characters = [event characters];
    self.charactersIgnoringModifiers = [event charactersIgnoringModifiers];
    self.modifiers = event.it_modifierFlags;
}

- (BOOL)eventIsShortcutPress:(NSEvent *)event {
    if (event.type != NSEventTypeKeyDown) {
        return NO;
    }
    return (([event it_modifierFlags] & kHotKeyModifierMask) == (_modifiers & kHotKeyModifierMask) &&
            [event keyCode] == _keyCode);
}

#pragma mark - NSCopying

- (instancetype)copyWithZone:(NSZone *)zone {
    iTermShortcut *theCopy = [[iTermShortcut alloc] init];
    theCopy.keyCode = self.keyCode;
    theCopy.modifiers = self.modifiers;
    theCopy.characters = self.characters;
    theCopy.charactersIgnoringModifiers = self.charactersIgnoringModifiers;
    return theCopy;
}

- (BOOL)smellsAccidental {
    if (!self.hasKeyCode) {
        return NO;
    }

    static NSSet<NSNumber *> *functionKeys = nil;
    static NSSet<NSNumber *> *navigationKeys = nil;
    static NSSet<NSNumber *> *commonTypingKeys = nil;  // Letters, digits, punctuation, etc.
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        functionKeys = [NSSet setWithArray:@[
            @(kVK_F1), @(kVK_F2), @(kVK_F3), @(kVK_F4), @(kVK_F5),
            @(kVK_F6), @(kVK_F7), @(kVK_F8), @(kVK_F9), @(kVK_F10),
            @(kVK_F11), @(kVK_F12), @(kVK_F13), @(kVK_F14), @(kVK_F15),
            @(kVK_F16), @(kVK_F17), @(kVK_F18), @(kVK_F19), @(kVK_F20)
        ]];

        navigationKeys = [NSSet setWithArray:@[
            @(kVK_LeftArrow), @(kVK_RightArrow),
            @(kVK_UpArrow), @(kVK_DownArrow),
            @(kVK_Home), @(kVK_End),
            @(kVK_PageUp), @(kVK_PageDown)
        ]];

        NSMutableSet *temp = [NSMutableSet set];

        // Alphanumerics
        [temp addObjectsFromArray:@[
            // 0-9
            @(kVK_ANSI_0),
            @(kVK_ANSI_1),
            @(kVK_ANSI_2),
            @(kVK_ANSI_3),
            @(kVK_ANSI_4),
            @(kVK_ANSI_5),
            @(kVK_ANSI_6),
            @(kVK_ANSI_7),
            @(kVK_ANSI_8),
            @(kVK_ANSI_9),

            // A-Z
            @(kVK_ANSI_A),
            @(kVK_ANSI_B),
            @(kVK_ANSI_C),
            @(kVK_ANSI_D),
            @(kVK_ANSI_E),
            @(kVK_ANSI_F),
            @(kVK_ANSI_G),
            @(kVK_ANSI_H),
            @(kVK_ANSI_I),
            @(kVK_ANSI_J),
            @(kVK_ANSI_K),
            @(kVK_ANSI_L),
            @(kVK_ANSI_M),
            @(kVK_ANSI_N),
            @(kVK_ANSI_O),
            @(kVK_ANSI_P),
            @(kVK_ANSI_Q),
            @(kVK_ANSI_R),
            @(kVK_ANSI_S),
            @(kVK_ANSI_T),
            @(kVK_ANSI_U),
            @(kVK_ANSI_V),
            @(kVK_ANSI_W),
            @(kVK_ANSI_X),
            @(kVK_ANSI_Y),
            @(kVK_ANSI_Z)
        ]];

        // Punctuation & symbols
        [temp addObjectsFromArray:@[
            @(kVK_ANSI_Grave),
            @(kVK_ANSI_Minus),
            @(kVK_ANSI_Equal),
            @(kVK_ANSI_LeftBracket),
            @(kVK_ANSI_RightBracket),
            @(kVK_ANSI_Backslash),
            @(kVK_ANSI_Semicolon),
            @(kVK_ANSI_Quote),
            @(kVK_ANSI_Comma),
            @(kVK_ANSI_Period),
            @(kVK_ANSI_Slash)
        ]];
        // Editing keys (not navigation)
        [temp addObjectsFromArray:@[
            @(kVK_Space),
            @(kVK_Delete),
            @(kVK_ForwardDelete),
            @(kVK_Tab),
            @(kVK_Return),
            @(kVK_Escape)
        ]];
        // ISO/JIS keys
        [temp addObjectsFromArray:@[
            @(kVK_ISO_Section),
            @(kVK_JIS_Yen),
            @(kVK_JIS_Underscore),
            @(kVK_JIS_KeypadComma),
            @(kVK_JIS_Eisu),
            @(kVK_JIS_Kana)
        ]];

        commonTypingKeys = [temp copy];
    });

    // Function keys generally don't smell accidental:
    if ([functionKeys containsObject:@(self.keyCode)]) {
        return NO;
    }

    const NSEventModifierFlags mask = NSEventModifierFlagCommand | NSEventModifierFlagControl;
    const BOOL hasCommandOrControl = (self.modifiers & mask) != 0;
    if (hasCommandOrControl) {
        return NO;
    }

    if ([commonTypingKeys containsObject:@(self.keyCode)]) {
        return YES;
    }
    if ([navigationKeys containsObject:@(self.keyCode)]) {
        return YES;
    }

    return NO;
}
@end
