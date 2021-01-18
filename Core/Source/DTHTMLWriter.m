//
//  DTHTMLWriter.m
//  DTCoreText
//
//  Created by Oliver Drobnik on 23.12.12.
//  Copyright (c) 2012 Drobnik.com. All rights reserved.
//

#import "DTHTMLWriter.h"
#import "NSDictionary+DTCoreText.h"
#import "DTCSSListStyle.h"
#import "DTCoreTextConstants.h"
#import "DTCoreTextFontDescriptor.h"
#import "DTCoreTextParagraphStyle.h"
#import "NSAttributedString+DTCoreText.h"
#import "NSAttributedString+HTML.h"
#import "DTTextAttachment.h"
#import "NSString+HTML.h"
#import "DTColorFunctions.h"

#import <DTFoundation/DTVersion.h>


@implementation DTHTMLWriter
{
    NSAttributedString *_attributedString;
    NSString *_HTMLString;
    CGFloat _textScale;
    BOOL _useAppleConvertedSpace;
    NSMutableDictionary *_styleLookup;
}

- (id)initWithAttributedString:(NSAttributedString *)attributedString
{
    self = [super init];
    
    if (self)
    {
        _attributedString = attributedString;

        _useAppleConvertedSpace = YES;

        // default is to leave px sizes as is
        _textScale = 1.0f;
        
        _paragraphTagName = @"p";
    }
    
    return self;
}

#pragma mark - Generating HTML

- (NSMutableArray *)_styleArrayForElement:(NSString *)elementName
{
    // get array of styles for element
    NSMutableArray *_styleArray = [_styleLookup objectForKey:elementName];
    
    if (!_styleArray)
    {
        // first time we see this element
        _styleArray = [[NSMutableArray alloc] init];
        [_styleLookup setObject:_styleArray forKey:elementName];
    }
    
    return _styleArray;
}

// checks the style against previous styles and returns the style class for this
- (NSString *)_styleClassForElement:(NSString *)elementName style:(NSString *)style
{
    // get array of styles for element
    NSMutableArray *_styleArray = [self _styleArrayForElement:elementName];
    
    NSInteger index = [_styleArray indexOfObject:style];
    
    if (index==NSNotFound)
    {
        // need to add this style
        [_styleArray addObject:style];
        index = [_styleArray count];
    }
    else
    {
        index++;
    }
    
    return [NSString stringWithFormat:@"%@%d", [elementName substringToIndex:1],(int)index];
}

- (NSString *)_tagRepresentationForListStyle:(DTCSSListStyle *)listStyle closingTag:(BOOL)closingTag listPadding:(CGFloat)listPadding inlineStyles:(BOOL)inlineStyles
{
    BOOL isOrdered = NO;
    
    NSString *typeString = nil;
    
    switch (listStyle.type)
    {
        case DTCSSListStyleTypeInherit:
        case DTCSSListStyleTypeDisc:
        {
            typeString = @"disc";
            isOrdered = NO;
            break;
        }
            
        case DTCSSListStyleTypeCircle:
        {
            typeString = @"circle";
            isOrdered = NO;
            break;
        }
            
        case DTCSSListStyleTypeSquare:
        {
            typeString = @"square";
            isOrdered = NO;
            break;
        }
            
        case DTCSSListStyleTypePlus:
        {
            typeString = @"plus";
            isOrdered = NO;
            break;
        }
            
        case DTCSSListStyleTypeUnderscore:
        {
            typeString = @"underscore";
            isOrdered = NO;
            break;
        }
            
        case DTCSSListStyleTypeImage:
        {
            typeString = @"image";
            isOrdered = NO;
            break;
        }
            
        case DTCSSListStyleTypeDecimal:
        {
            typeString = @"decimal";
            isOrdered = YES;
            break;
        }
            
        case DTCSSListStyleTypeDecimalLeadingZero:
        {
            typeString = @"decimal-leading-zero";
            isOrdered = YES;
            break;
        }
            
        case DTCSSListStyleTypeUpperAlpha:
        {
            typeString = @"upper-alpha";
            isOrdered = YES;
            break;
        }
            
        case DTCSSListStyleTypeUpperLatin:
        {
            typeString = @"upper-latin";
            isOrdered = YES;
            break;
        }
            
        case DTCSSListStyleTypeUpperRoman:
        {
            typeString = @"upper-roman";
            isOrdered = YES;
            break;
        }
            
        case DTCSSListStyleTypeLowerAlpha:
        {
            typeString = @"lower-alpha";
            isOrdered = YES;
            break;
        }
            
        case DTCSSListStyleTypeLowerLatin:
        {
            typeString = @"lower-latin";
            isOrdered = YES;
            break;
        }
            
        case DTCSSListStyleTypeLowerRoman:
        {
            typeString = @"lower-roman";
            isOrdered = YES;
            break;
        }
            
        case DTCSSListStyleTypeNone:
        {
            typeString = @"none";
            
            break;
        }
            
        case DTCSSListStyleTypeInvalid:
        {
            break;
        }
    }
    
    if (closingTag)
    {
        if (isOrdered)
        {
            return @"</ol>";
        }
        else
        {
            return @"</ul>";
        }
    }
    else
    {
        if (isOrdered)
        {
            return @"<ol>";
        }
        else
        {
            return @"<ul>";
        }
    }
}

- (void)_buildOutput
{
    [self _buildOutputAsHTMLFragment:NO];
}

- (void)_buildOutputAsHTMLFragment:(BOOL)fragment
{
    // reusable styles
    _styleLookup = [[NSMutableDictionary alloc] init];
    
    NSString *plainString = [_attributedString string];
    
    // divide the string into it's blocks (we assume that these are the P)
    NSArray *paragraphs = [plainString componentsSeparatedByString:@"\n"];
    
    NSMutableString *retString = [NSMutableString string];
    
    NSInteger location = 0;
    
    NSArray *previousListStyles = nil;
    
    for (NSUInteger i=0; i<[paragraphs count]; i++)
    {
        NSString *oneParagraph = [paragraphs objectAtIndex:i];
        NSRange paragraphRange = NSMakeRange(location, [oneParagraph length]);
        
        // skip empty paragraph at the end
        if (i==[paragraphs count]-1)
        {
            if (!paragraphRange.length)
            {
                continue;
            }
        }
        
        __block BOOL needsToRemovePrefix = NO;
        
        BOOL fontIsBlockLevel = NO;
        
        // check if font is same in the entire paragraph
        NSRange fontEffectiveRange;
        CTFontRef paragraphFont = (__bridge CTFontRef)[_attributedString attribute:(id)kCTFontAttributeName atIndex:paragraphRange.location longestEffectiveRange:&fontEffectiveRange inRange:paragraphRange];
        
        if (NSEqualRanges(paragraphRange, fontEffectiveRange))
        {
            fontIsBlockLevel = YES;
        }
        
        // next paragraph start
        location = location + paragraphRange.length + 1;
        
        NSDictionary *paraAttributes = [_attributedString attributesAtIndex:paragraphRange.location effectiveRange:NULL];
        
        // lets see if we have a list style
        NSArray *currentListStyles = [paraAttributes objectForKey:DTTextListsAttribute];
        
        DTCSSListStyle *effectiveListStyle = [currentListStyles lastObject];
        
        // retrieve the paragraph style
        DTCoreTextParagraphStyle *paragraphStyle = [paraAttributes paragraphStyle];
        NSString *paraStyleString = nil;
        
        if (paragraphStyle && !effectiveListStyle)
        {
            if (_textScale!=1.0f)
            {
                paragraphStyle.minimumLineHeight = round(paragraphStyle.minimumLineHeight / _textScale);
                paragraphStyle.maximumLineHeight = round(paragraphStyle.maximumLineHeight / _textScale);
                
                paragraphStyle.paragraphSpacing = round(paragraphStyle.paragraphSpacing/ _textScale);
                paragraphStyle.paragraphSpacingBefore = round(paragraphStyle.paragraphSpacingBefore / _textScale);
                
                paragraphStyle.firstLineHeadIndent = round(paragraphStyle.firstLineHeadIndent / _textScale);
                paragraphStyle.headIndent = round(paragraphStyle.headIndent / _textScale);
                paragraphStyle.tailIndent = round(paragraphStyle.tailIndent / _textScale);
            }
            
            paraStyleString = [paragraphStyle cssStyleRepresentation];
        }
        
        if (!paraStyleString)
        {
            paraStyleString = @"";
        }
        
        if (fontIsBlockLevel)
        {
            if (paragraphFont)
            {
                DTCoreTextFontDescriptor *desc = [DTCoreTextFontDescriptor fontDescriptorForCTFont:paragraphFont];
                
                if (_textScale!=1.0f)
                {
                    desc.pointSize /= _textScale;
                }
                
                NSString *paraFontStyle = [desc cssStyleRepresentation];
                
                if (paraFontStyle)
                {
                    paraStyleString = [paraStyleString stringByAppendingString:paraFontStyle];
                }
            }
        }
        
        NSString *blockElement;
        
        // close until we are at current or nil
        if ([previousListStyles count]>[currentListStyles count])
        {
            NSMutableArray *closingStyles = [previousListStyles mutableCopy];
            
            do
            {
                DTCSSListStyle *closingStyle = [closingStyles lastObject];
                
                if (closingStyle == effectiveListStyle)
                {
                    break;
                }
                
                // end of a list block
                [retString appendString:[self _tagRepresentationForListStyle:closingStyle closingTag:YES listPadding:0 inlineStyles:fragment]];
                
                [closingStyles removeLastObject];
                
                previousListStyles = closingStyles;
            }
            while ([closingStyles count]);
        }
        
        if (effectiveListStyle)
        {
            // next text needs to have list prefix removed
            needsToRemovePrefix = YES;
            
            
            // get lists that need to be opened here
            NSArray *listsToOpen = nil;
            
            if (!previousListStyles)
            {
                listsToOpen = currentListStyles;
            }
            else
            {
                NSMutableArray *tmpArray = [NSMutableArray array];
                
                for (DTCSSListStyle *oneList in currentListStyles)
                {
                    NSRange listRange = [_attributedString rangeOfTextList:oneList atIndex:paragraphRange.location];
                    
                    if (listRange.location == paragraphRange.location)
                    {
                        // lists starts here
                        [tmpArray addObject:oneList];
                    }
                }

                if ([tmpArray count])
                {
                    listsToOpen = [tmpArray copy];
                }
            }
            
            [listsToOpen enumerateObjectsUsingBlock:^(DTCSSListStyle *oneList, NSUInteger idx, BOOL *stop) {
                
                // only padding can be reconstructed so far
                CGFloat listPadding = (paragraphStyle.headIndent - paragraphStyle.firstLineHeadIndent) / self.textScale;
                
                // beginning of a list block
                [retString appendString:[self _tagRepresentationForListStyle:oneList closingTag:NO listPadding:listPadding inlineStyles:fragment]];
                
                // all but the effective list need an extra LI
                if (oneList != effectiveListStyle)
                {
                    [retString appendString:@"<li>"];
                }
            }];
            
            blockElement = @"li";
        }
        else
        {
            blockElement = _paragraphTagName;
        }
        
        // find which custom attributes are for the entire paragraph
        NSDictionary *HTMLAttributes = [_attributedString HTMLAttributesAtIndex:paragraphRange.location];
        NSMutableDictionary *paragraphLevelHTMLAttributes = [NSMutableDictionary dictionary];
        
        [HTMLAttributes enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
            
            // check if range is longer than current paragraph
            NSRange attributeEffectiveRange = [self.attributedString rangeOfHTMLAttribute:key atIndex:paragraphRange.location];
            
            if (NSIntersectionRange(attributeEffectiveRange, paragraphRange).length == paragraphRange.length)
            {
                [paragraphLevelHTMLAttributes setObject:value forKey:key];
            }
        }];
        
        [retString appendFormat:@"<%@>", blockElement];

        [_attributedString enumerateAttributesInRange:paragraphRange options:0 usingBlock:^(NSDictionary *attributes, NSRange spanRange, BOOL *stopEnumerateAttributes) {

            BOOL bold = NO;
            BOOL italic = NO;
            BOOL underline = [[attributes objectForKey:(id)kCTUnderlineStyleAttributeName] unsignedIntValue] > 0;

            DTCoreTextFontDescriptor *fontDescriptor = [attributes fontDescriptor];
            bold = fontDescriptor.boldTrait;
            italic = fontDescriptor.italicTrait;

            NSString *boldTagName = @"strong";
            NSString *italicTagName = @"i";
            NSString *underlineTagName = @"u";

            if (bold)
            {
                [retString appendFormat:@"<%@>", boldTagName];
            }
            if (italic) {
                [retString appendFormat:@"<%@>", italicTagName];
            }
            if (underline) {
                [retString appendFormat:@"<%@>", underlineTagName];
            }
            
            if (!attributes[DTFieldAttribute]) {
                [retString appendString:[_attributedString attributedSubstringFromRange:spanRange].string];
            }
            
            if (bold) {
                [retString appendFormat:@"</%@>", boldTagName];
            }
            if (italic) {
                [retString appendFormat:@"</%@>", italicTagName];
            }
            if (underline) {
                [retString appendFormat:@"</%@>", underlineTagName];
            }
        }];
        
        if ([blockElement isEqualToString:@"li"])
        {
            BOOL shouldCloseLI = YES;

            NSUInteger nextParagraphStart = NSMaxRange([plainString paragraphRangeForRange:paragraphRange]);
            
            if (nextParagraphStart < [plainString length])
            {
                NSArray *nextListStyles = [_attributedString attribute:DTTextListsAttribute atIndex:nextParagraphStart effectiveRange:NULL];
                
                // LI are only closed if there is not a deeper list level following
                if (nextListStyles && ([nextListStyles indexOfObjectIdenticalTo:effectiveListStyle]!=NSNotFound) && [nextListStyles count] > [currentListStyles count])
                {
                    // deeper list following
                    shouldCloseLI = NO;
                }
            }
            
            if (shouldCloseLI)
            {
                [retString appendString:@"</li>"];
            }
        }
        else
        {
            // other blocks are always closed
            [retString appendFormat:@"</%@>", blockElement];
        }
        
        previousListStyles = [currentListStyles copy];
    }  // end of P loop

    
    // close list if still open
    if ([previousListStyles count])
    {
        NSMutableArray *closingStyles = [previousListStyles mutableCopy];
        
        do
        {
            DTCSSListStyle *closingStyle = [closingStyles lastObject];
            
            // end of a list block
            [retString appendString:[self _tagRepresentationForListStyle:closingStyle closingTag:YES listPadding:0 inlineStyles:fragment]];
            
            if ([closingStyles count]>1)
            {
                [retString appendString:@"</li>"];
            }
            
            [closingStyles removeLastObject];
        }
        while ([closingStyles count]);
    }
        
    NSMutableString *output = [NSMutableString string];
    
    if (_useAppleConvertedSpace)
    {
        NSString *convertedSpaces = [retString stringByAddingAppleConvertedSpace];
        
        [output appendString:convertedSpaces];
    }
    else
    {
        [output appendString:retString];
    }
    
    _HTMLString = output;
}

#pragma mark - Public

- (NSString *)HTMLString
{
    if (!_HTMLString)
    {
        [self _buildOutput];
    }
    
    return _HTMLString;
}

- (NSString *)HTMLFragment
{
    if (!_HTMLString)
    {
        [self _buildOutputAsHTMLFragment:true];
    }
    
    return _HTMLString;
}

#pragma mark - Properties

@synthesize attributedString = _attributedString;
@synthesize textScale = _textScale;
@synthesize useAppleConvertedSpace = _useAppleConvertedSpace;

@end
