//
//  CurvedTextLayer.m
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/1/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

#import <CoreText/CoreText.h>
#import <QuartzCore/QuartzCore.h>

#import "CurvedTextLayer.h"
#import "PathUtil.h"


@implementation CurvedTextLayer

static const CGFloat TEXT_SHADOW_WIDTH = 2.5;


+(void)drawString:(NSString *)string alongPath:(CGPathRef)path offset:(CGFloat)offset stroke:(BOOL)stroke color:(NSColor *)color context:(CGContextRef)ctx
{
	CGContextSetShadowWithColor( ctx, CGSizeMake(0,0), 0.0, NULL );

	if ( stroke ) {

		CGContextSetLineWidth( ctx, TEXT_SHADOW_WIDTH);
		CGContextSetLineJoin( ctx, kCGLineJoinRound );
		CGContextSetTextDrawingMode( ctx, kCGTextFillStroke );
		CGContextSetFillColorWithColor(ctx, color.CGColor);
		CGContextSetStrokeColorWithColor(ctx, color.CGColor);

	} else {

		CGContextSetTextDrawingMode( ctx, kCGTextFill );
		CGContextSetFillColorWithColor(ctx, color.CGColor);
		CGContextSetStrokeColorWithColor(ctx, NULL);
		CGContextSetTextDrawingMode(ctx, kCGTextFill);
	}

	CTFontRef ctFont = CTFontCreateUIFontForLanguage( kCTFontUIFontSystem, 14.0, NULL );

	CGContextSaveGState(ctx);
	CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
	CGContextSetTextPosition(ctx, 0, 0);

	// get array of glyph widths
	NSAttributedString * attrString = [[NSAttributedString alloc] initWithString:string attributes:@{ (NSString *)kCTFontAttributeName : (__bridge id)ctFont }];
	CTLineRef	line		= CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)attrString);
	CFArrayRef	runArray	= CTLineGetGlyphRuns(line);
	CFIndex		runCount	= CFArrayGetCount(runArray);

	for ( CFIndex runIndex = 0; runIndex < runCount; runIndex++) {
		CTRunRef	run				= (CTRunRef)CFArrayGetValueAtIndex( runArray, runIndex );
		CFIndex		runGlyphCount	= CTRunGetGlyphCount( run );
		CTFontRef	runFont			= CFDictionaryGetValue( CTRunGetAttributes(run), kCTFontAttributeName );
		CGGlyph		glyphs[ runGlyphCount ];
		CGPoint		glyphPositions[ runGlyphCount ];
		CGPoint		positions[ runGlyphCount ];
		CTRunGetGlyphs( run, CFRangeMake(0,runGlyphCount), glyphs);
		CTRunGetPositions( run, CFRangeMake(0,runGlyphCount), glyphPositions );

		for ( CFIndex runGlyphIndex = 0; runGlyphIndex < runGlyphCount; runGlyphIndex++ ) {

			CGContextSaveGState(ctx);

			CGPoint pos;
			CGFloat angle, length;
			PathPositionAndAngleForOffset( path, offset+glyphPositions[runGlyphIndex].x, &pos, &angle, &length );

			NSInteger segmentCount = 0;
			while ( runGlyphIndex+segmentCount < runGlyphCount ) {
				positions[segmentCount].x = glyphPositions[runGlyphIndex+segmentCount].x - glyphPositions[runGlyphIndex].x;
				positions[segmentCount].y = 0;
				++segmentCount;
				if ( glyphPositions[runGlyphIndex+segmentCount].x >= length )
					break;
			}

			// We use a different affine transform for each glyph segment, to position and rotate it
			// based on its calculated position along the path.
			CGContextTranslateCTM( ctx, pos.x, pos.y );
			CGContextRotateCTM( ctx, angle );
			CGContextScaleCTM( ctx, 1.0, -1.0 );

			// draw text
			CTFontDrawGlyphs( runFont, &glyphs[runGlyphIndex], positions, segmentCount, ctx );
			
			CGContextRestoreGState(ctx);

			runGlyphIndex += segmentCount - 1;
		}
	}
	CFRelease(line);
	CFRelease(ctFont);

	CGContextRestoreGState(ctx);
}


+(void)drawString:(NSString *)string alongPath:(CGPathRef)path offset:(CGFloat)offset color:(NSColor *)color shadowColor:(NSColor *)shadowColor context:(CGContextRef)ctx
{
	[self drawString:string alongPath:path offset:offset stroke:YES color:shadowColor context:ctx];
	[self drawString:string alongPath:path offset:offset stroke:NO  color:color		  context:ctx];
}

+(void)drawString:(NSString *)string centeredOnPoint:(CGPoint)center width:(CGFloat)lineWidth font:(NSFont *)font color:(UIColor *)color shadowColor:(UIColor *)shadowColor context:(CGContextRef)ctx
{
	CGContextSetTextMatrix(ctx, CGAffineTransformMakeScale(1.0, -1.0)); // view's coordinates are flipped

#if TARGET_OS_IPHONE
	if ( font == nil )
		font = [UIFont systemFontOfSize:10];
	NSAttributedString * s1 = [[NSAttributedString alloc] initWithString:string attributes:@{ NSForegroundColorAttributeName : (id)color.CGColor,		NSFontAttributeName : font }];
	NSAttributedString * s2 = [[NSAttributedString alloc] initWithString:string attributes:@{ NSForegroundColorAttributeName : (id)shadowColor.CGColor,	NSFontAttributeName : font }];
#else
	if ( font == nil )
		font = [NSFont systemFontOfSize:10];
	NSAttributedString * s1 = [[NSAttributedString alloc] initWithString:name attributes:@{NSForegroundColorAttributeName : self.textColor}];
#endif

	CGFloat lineHeight = font.lineHeight;

	// compute number of characters in each line of text
	const NSInteger maxLines = 20;
	NSInteger lineCount = 0;
	NSInteger charPerLine[ maxLines ];
	NSInteger charCount = CFAttributedStringGetLength( (__bridge CFAttributedStringRef)s1 );
	CTTypesetterRef typesetter = CTTypesetterCreateWithAttributedString( (__bridge CFAttributedStringRef)s1 );
	if ( lineWidth == 0 ) {
		charPerLine[lineCount++] = charCount;
	} else {
		NSInteger start = 0;
		while ( lineCount < maxLines ) {
			CFIndex count = CTTypesetterSuggestLineBreak( typesetter, start, lineWidth );
			charPerLine[ lineCount++ ] = count;
			start += count;
			if ( start >= charCount )
				break;
		}
	}

	// iterate over lines
	NSInteger start = 0;
	for ( NSInteger line = 0; line < lineCount; ++line )  {
		CFIndex count = charPerLine[ line ];
		CTLineRef ct1 = CTTypesetterCreateLine( typesetter, CFRangeMake(start,count) );
		CTLineRef ct2 = CTLineCreateWithAttributedString( (__bridge CFAttributedStringRef)[s2 attributedSubstringFromRange:NSMakeRange(start,count)] );

		// center on point
		CGRect textRect = CTLineGetBoundsWithOptions( ct1, 0 );
		CGPoint point = {
			round( center.x - (textRect.origin.x+textRect.size.width)/2 ),
			round( center.y + lineHeight*(1 + line - lineCount/2) )
		};

		// draw shadow
		CGContextSetShadowWithColor( ctx, CGSizeMake(0,0), 0.0, NULL );
		CGContextSetLineWidth( ctx, TEXT_SHADOW_WIDTH);
		CGContextSetLineJoin( ctx, kCGLineJoinRound );
		CGContextSetStrokeColorWithColor(ctx, shadowColor.CGColor);
		CGContextSetFillColorWithColor(ctx, shadowColor.CGColor);
		CGContextSetTextDrawingMode(ctx, kCGTextFillStroke);
		CGContextSetTextPosition(ctx, point.x, point.y);	// this applies a transform, so do it after flipping
		CTLineDraw(ct2, ctx);

		// draw text
		CGContextSetTextDrawingMode(ctx, kCGTextFill);
		CGContextSetFillColorWithColor(ctx, color.CGColor);
		CGContextSetTextPosition(ctx, point.x, point.y);	// this applies a transform, so do it after flipping
		CTLineDraw(ct1, ctx);

		CFRelease(ct1);
		CFRelease(ct2);

		start += count;
	}

	CFRelease(typesetter);
	CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
}

@end
