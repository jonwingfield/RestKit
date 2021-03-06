//
//  RKXMLParserLibXML.m
//
//  Created by Jeremy Ellison on 2011-02-28.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import <libxml2/libxml/parser.h>
#import <libxml2/libxml/encoding.h>
#import <libxml2/libxml/xmlwriter.h>
#import "RKXMLParserLibXML.h"

#define XML_ENCODING "ISO-8859-1"

@implementation RKXMLParserLibXML

- (id)parseNode:(xmlNode*)node {
    NSMutableArray* nodes = [NSMutableArray array];
    NSMutableDictionary* attrs = [NSMutableDictionary dictionary];
    
    xmlNode* currentNode = NULL;
    for (currentNode = node; currentNode; currentNode = currentNode->next) {
        if (currentNode->type == XML_ELEMENT_NODE) {
            NSString* nodeName = [NSString stringWithCString:(char*)currentNode->name encoding:NSUTF8StringEncoding];
            id val = [self parseNode:currentNode->children];
            if ([val isKindOfClass:[NSString class]]) {
                if ([val isEqualToString:@"false"]) {
                    val = [NSNumber numberWithBool:NO];
                } else if ([val isEqualToString:@"true"]) {
                    val = [NSNumber numberWithBool:YES];
                } else if ([val isEqualToString:@""]) {
                    val = nil;
                }
                
                id oldVal = [attrs valueForKey:nodeName];
                if (nil == oldVal) {
                    [attrs setValue:val forKey:nodeName];
                } else if ([oldVal isKindOfClass:[NSMutableArray class]]) {
                    [oldVal addObject:val];
                } else {
                    NSMutableArray* array = [NSMutableArray arrayWithObjects:oldVal, val, nil];
                    [attrs setValue:array forKey:nodeName];
                }
                
                // Only add attributes to nodes if there actually is one.
                if (![nodes containsObject:attrs]) {
                    [nodes addObject:attrs];
                }
            } else {
                NSDictionary* elem = [NSDictionary dictionaryWithObject:val forKey:nodeName];
                [nodes addObject:elem];
            }
            xmlElement* element = (xmlElement*)currentNode;
            xmlAttribute* currentAttribute = NULL;
            for (currentAttribute = (xmlAttribute*)element->attributes; currentAttribute; currentAttribute = (xmlAttribute*)currentAttribute->next) {
                NSString* name = [NSString stringWithCString:(char*)currentAttribute->name encoding:NSUTF8StringEncoding];
                xmlChar* str = xmlNodeGetContent((xmlNode*)currentAttribute);
                NSString* val = [NSString stringWithCString:(char*)str encoding:NSUTF8StringEncoding];
                xmlFree(str);
                [attrs setValue:val forKey:name];
                // Only add attributes to nodes if there actually is one.
                if (![nodes containsObject:attrs]) {
                    [nodes addObject:attrs];
                }
            }
        } else if (currentNode->type == XML_TEXT_NODE) {
            xmlChar* str = xmlNodeGetContent(currentNode);
            NSString* part = [NSString stringWithCString:(const char*)str encoding:NSUTF8StringEncoding];
            if ([[part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] > 0) {
                [nodes addObject:part];
            }
            xmlFree(str);
        }
    }
    if ([nodes count] == 1) {
        return [nodes objectAtIndex:0];
    }
    if ([nodes count] == 0) {
        return @"";
    }
    if (YES || [nodes containsObject:attrs]) {
        // We have both attributes and children. merge everything together.
        NSMutableDictionary* results = [NSMutableDictionary dictionary];
        for (NSDictionary* dict in nodes) {
            for (NSString* key in dict) {
                id value = [dict valueForKey:key];
                id currentValue = [results valueForKey:key];
                if (nil == currentValue) {
                    [results setValue:value forKey:key];
                } else if ([currentValue isKindOfClass:[NSMutableArray class]]) {
                    [currentValue addObject:value];
                } else {
                    NSMutableArray* array = [NSMutableArray arrayWithObjects: currentValue, value, nil];
                    [results setValue:array forKey:key];
                }
            }
        }
        return results;
    }
    return nodes;
}

- (NSDictionary*)parseXML:(NSString*)xml {
    xmlParserCtxtPtr ctxt; /* the parser context */
    xmlDocPtr doc; /* the resulting document tree */
    id result = nil;;

    /* create a parser context */
    ctxt = xmlNewParserCtxt();
    if (ctxt == NULL) {
        fprintf(stderr, "Failed to allocate parser context\n");
        return nil;
    }
    /* Parse the string. */
    const char* buffer = [xml cStringUsingEncoding:NSUTF8StringEncoding];
    doc = xmlParseMemory(buffer, strlen(buffer));
    
    /* check if parsing suceeded */
    if (doc == NULL) {
        fprintf(stderr, "Failed to parse\n");
    } else {
	    /* check if validation suceeded */
        if (ctxt->valid == 0) {
	        fprintf(stderr, "Failed to validate\n");
        }
        
        /* Parse Doc into Dict */
        result = [self parseNode:doc->xmlRootNode];
        
	    /* free up the resulting document */
	    xmlFreeDoc(doc);
    }
    /* free up the parser context */
    xmlFreeParserCtxt(ctxt);
    return result;
}

- (id)objectFromString:(NSString*)string error:(NSError **)error {
    // TODO: Add error handling...
    return [self parseXML:string];
}

- (void)parseDictionary:(id)object with:(xmlTextWriterPtr)writer 
{
    for (id key in object) {
        id value = [object objectForKey:key];
        if ([value isKindOfClass:[NSDictionary class]]) {
            xmlTextWriterStartElement(writer, BAD_CAST [key cStringUsingEncoding:NSUTF8StringEncoding]);
            [self parseDictionary:value with:writer];
            xmlTextWriterEndElement(writer);
        } else if ([value isKindOfClass:[NSArray class]]) {
            for (id item in value) {
                if ([item isKindOfClass:[NSString class]]) {
                    xmlTextWriterWriteElement(writer, BAD_CAST [key cStringUsingEncoding:NSUTF8StringEncoding], BAD_CAST [item UTF8String]);
                } else {
                    xmlTextWriterStartElement(writer, BAD_CAST [key cStringUsingEncoding:NSUTF8StringEncoding]);                
                    [self parseDictionary:item with:writer];
                    xmlTextWriterEndElement(writer);
                }
            }
        } else {
            xmlTextWriterWriteElement(writer, BAD_CAST [key cStringUsingEncoding:NSUTF8StringEncoding], BAD_CAST [[NSString stringWithFormat:@"%@", value] cStringUsingEncoding:NSUTF8StringEncoding]);
        }
    }    
}

- (NSString*)stringFromObject:(id)object error:(NSError **)error {    
    int rc;
    xmlTextWriterPtr writer;
    xmlBufferPtr buf;
    
    /* Create a new XML buffer, to which the XML document will be
     * written */
    buf = xmlBufferCreate();
    if (buf == 0) {
        [NSException raise:@"Error creating buffer to write XML!" format:@""];
        return nil;
    }
    
    // create an xmlTextWriter that just writes to a memory buffer
    writer = xmlNewTextWriterMemory(buf, 0); // 0 means no compresion
    if (writer == 0) {
        [NSException raise:@"Error creating text writer" format:@""];
        return nil;
    }
    
    rc = xmlTextWriterStartDocument(writer, NULL, XML_ENCODING, NULL);
    
    [self parseDictionary:object with:writer];
    
    rc = xmlTextWriterEndDocument(writer);
    xmlFreeTextWriter(writer);
    
    NSString* result = [NSString stringWithCString:(char*)buf->content encoding:NSUTF8StringEncoding];    
    
    xmlBufferFree(buf);
    
    return result;
}

@end
