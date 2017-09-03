//
//  EXTRuntimeExtensions.m
//  extobjc
//
//  Created by Justin Spahr-Summers on 2011-03-05.
//  Copyright (C) 2012 Justin Spahr-Summers.
//  Released under the MIT license.
//

#import "RACEXTRuntimeExtensions.h"

#import <ctype.h>
#import <Foundation/Foundation.h>
#import <libkern/OSAtomic.h>
#import <objc/message.h>
#import <pthread.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>

/******重要*********/
//The string starts with a T followed by the @encode type and a comma, and finishes with a V followed by the name of the backing instance variable.
/*
 R 			The property is read-only (readonly).
 C 			The property is a copy of the value last assigned (copy).
 & 			The property is a reference to the value last assigned (retain).
 N 			The property is non-atomic (nonatomic).
 G<name>		The property defines a custom getter selector name. The name follows the G (for
 example, GcustomGetter,).
 S<name>		The property defines a custom setter selector name. The name follows the S (for
 example, ScustomSetter:,).
 D 			The property is dynamic (@dynamic).
 W 			The property is a weak reference (__weak).
 P 			The property is eligible for garbage collection.
 t<encoding>	Specifies the type using old-style encoding.
 
 ref:
    https://developer.apple.com/library/content/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtPropertyIntrospection.html#//apple_ref/doc/uid/TP40008048-CH101-SW5
    https://developer.apple.com/library/content/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html
 
 ####example:
 https://developer.apple.com/library/content/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtPropertyIntrospection.html#//apple_ref/doc/uid/TP40008048-CH101-SW5
 
 */
rac_propertyAttributes *rac_copyPropertyAttributes (objc_property_t property) {
    const char * const attrString = property_getAttributes(property);//像这样"T@\"NSString\",&,N,V_name"
    if (!attrString) {
        fprintf(stderr, "ERROR: Could not get attribute string from property %s\n", property_getName(property));
        return NULL;
    }

    if (attrString[0] != 'T') {
        fprintf(stderr, "ERROR: Expected attribute string \"%s\" for property %s to start with 'T'\n", attrString, property_getName(property));
        return NULL;
    }

    const char *typeString = attrString + 1;//绕过T
    const char *next = NSGetSizeAndAlignment(typeString, NULL, NULL);//获取指针的大小，返回第二个数据，比如typeString是"@\"NSString\",&,N,V_name"，那么next的指针指向第一个逗号。这是专门针对@encode的字符
    if (!next) {
        fprintf(stderr, "ERROR: Could not read past type in attribute string \"%s\" for property %s\n", attrString, property_getName(property));
        return NULL;
    }

    size_t typeLength = (size_t)(next - typeString);
    if (!typeLength) {
        fprintf(stderr, "ERROR: Invalid type in attribute string \"%s\" for property %s\n", attrString, property_getName(property));
        return NULL;
    }

    // allocate enough space for the structure and the type string (plus a NUL)
    /*
     calloc() 函数用来动态地分配内存空间并初始化为 0，其原型为：
     void* calloc (size_t num, size_t size);
     calloc() 在内存中动态地分配 num 个长度为 size 的连续空间，并将每一个字节都初始化为 0。所以它的结果是分配了 num*size 个字节长度的内存空间，并且每个字节的值都是0
     */
    
    //rac_propertyAttributes中的可变数组的长度是没有确定的，所以要加上长度
    rac_propertyAttributes *attributes = calloc(1, sizeof(rac_propertyAttributes) + typeLength + 1);
    if (!attributes) {
        fprintf(stderr, "ERROR: Could not allocate rac_propertyAttributes structure for attribute string \"%s\" for property %s\n", attrString, property_getName(property));
        return NULL;
    }

    // copy the type string
    strncpy(attributes->type, typeString, typeLength);
    attributes->type[typeLength] = '\0';//结束的标志，这就是为什么calloc的时候size是sizeof(rac_propertyAttributes) + typeLength + 1)，type[7]含有八个值

    // if this is an object type, and immediately followed by a quoted string...
    // @encode(id) = @, * -> char*
    if (typeString[0] == *(@encode(id)) && typeString[1] == '"') {
        // we should be able to extract a class name
        const char *className = typeString + 2;
        /*
         strchr() 用来查找某字符在字符串中首次出现的位置，其原型为：
         char * strchr (const char *str, int c);
         【参数】str 为要查找的字符串，c 为要查找的字符。
         返回值】如果找到指定的字符则返回该字符所在地址，否则返回 NULL。
         */
        next = strchr(className, '"');

        if (!next) {
            fprintf(stderr, "ERROR: Could not read class name in attribute string \"%s\" for property %s\n", attrString, property_getName(property));
            return NULL;
        }

        if (className != next) {
            size_t classNameLength = (size_t)(next - className);
            char trimmedName[classNameLength + 1];

            strncpy(trimmedName, className, classNameLength);
            trimmedName[classNameLength] = '\0';

            // attempt to look up the class in the runtime
            attributes->objectClass = objc_getClass(trimmedName);
        }
    }

    if (*next != '\0') {
        // skip past any junk before the first flag
        next = strchr(next, ',');
    }

    while (next && *next == ',') {
        char flag = next[1];
        next += 2;

        switch (flag) {
        case '\0':
            break;

        case 'R':
            attributes->readonly = YES;
            break;

        case 'C':
            attributes->memoryManagementPolicy = rac_propertyMemoryManagementPolicyCopy;
            break;

        case '&':
            attributes->memoryManagementPolicy = rac_propertyMemoryManagementPolicyRetain;
            break;

        case 'N':
            attributes->nonatomic = YES;
            break;

        case 'G':
        case 'S':
            {
                const char *nextFlag = strchr(next, ',');
                SEL name = NULL;

                if (!nextFlag) {
                    // assume that the rest of the string is the selector
                    const char *selectorString = next;
                    next = "";

                    name = sel_registerName(selectorString);
                } else {
                    size_t selectorLength = (size_t)(nextFlag - next);
                    if (!selectorLength) {
                        fprintf(stderr, "ERROR: Found zero length selector name in attribute string \"%s\" for property %s\n", attrString, property_getName(property));
                        goto errorOut;
                    }

                    char selectorString[selectorLength + 1];

                    strncpy(selectorString, next, selectorLength);
                    selectorString[selectorLength] = '\0';

                    name = sel_registerName(selectorString);
                    next = nextFlag;
                }

                if (flag == 'G')
                    attributes->getter = name;
                else
                    attributes->setter = name;
            }

            break;

        case 'D':
            attributes->dynamic = YES;
            attributes->ivar = NULL;
            break;

        case 'V':
            // assume that the rest of the string (if present) is the ivar name
            if (*next == '\0') {
                // if there's nothing there, let's assume this is dynamic
                attributes->ivar = NULL;
            } else {
                attributes->ivar = next;
                next = "";
            }

            break;

        case 'W':
            attributes->weak = YES;
            break;

        case 'P':
            attributes->canBeCollected = YES;
            break;

        case 't':
            fprintf(stderr, "ERROR: Old-style type encoding is unsupported in attribute string \"%s\" for property %s\n", attrString, property_getName(property));

            // skip over this type encoding
            while (*next != ',' && *next != '\0')
                ++next;

            break;

        default:
            fprintf(stderr, "ERROR: Unrecognized attribute string flag '%c' in attribute string \"%s\" for property %s\n", flag, attrString, property_getName(property));
        }
    }

    if (next && *next != '\0') {
        fprintf(stderr, "Warning: Unparsed data \"%s\" in attribute string \"%s\" for property %s\n", next, attrString, property_getName(property));
    }

    if (!attributes->getter) {
        // use the property name as the getter by default
        attributes->getter = sel_registerName(property_getName(property));
    }

    if (!attributes->setter) {
        const char *propertyName = property_getName(property);
        size_t propertyNameLength = strlen(propertyName);

        // we want to transform the name to setProperty: style
        size_t setterLength = propertyNameLength + 4;

        char setterName[setterLength + 1];
        strncpy(setterName, "set", 3);
        strncpy(setterName + 3, propertyName, propertyNameLength);

        // capitalize property name for the setter
        setterName[3] = (char)toupper(setterName[3]);

        setterName[setterLength - 1] = ':';
        setterName[setterLength] = '\0';

        attributes->setter = sel_registerName(setterName);
    }

    return attributes;

errorOut:
    free(attributes);
    return NULL;
}

Method rac_getImmediateInstanceMethod (Class aClass, SEL aSelector) {
    unsigned methodCount = 0;
    Method *methods = class_copyMethodList(aClass, &methodCount);
    Method foundMethod = NULL;

    for (unsigned methodIndex = 0;methodIndex < methodCount;++methodIndex) {
        if (method_getName(methods[methodIndex]) == aSelector) {
            foundMethod = methods[methodIndex];
            break;
        }
    }

    free(methods);
    return foundMethod;
}
