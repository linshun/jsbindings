/*
 * JS Bindings: https://github.com/zynga/jsbindings
 *
 * Copyright (c) 2012 Zynga Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */


#import "js_bindings_config.h"
#ifdef JSB_INCLUDE_CHIPMUNK

#import "jsapi.h"
#import "jsfriendapi.h"

#import "js_bindings_chipmunk_manual.h"
#import "js_bindings_basic_conversions.h"
#import "js_bindings_core.h"
#import "uthash.h"


#pragma mark - convertions

// XXX:
// XXX: It should create "normal" objects instead of TypedArray objects
// XXX: And the "constructor" should be in JS, like cc.rect(), cc.size() and cc.p()
// XXX:
JSBool jsval_to_cpBB( JSContext *cx, jsval vp, cpBB *ret )
{
	JSObject *tmp_arg;
	JSBool ok = JS_ValueToObject( cx, vp, &tmp_arg );
	JSB_PRECONDITION( ok, "Error converting value to object");
	JSB_PRECONDITION( JS_IsTypedArrayObject( tmp_arg, cx ), "Not a TypedArray object");
	JSB_PRECONDITION( JS_GetTypedArrayByteLength( tmp_arg, cx ) == sizeof(cpFloat)*4, "Invalid length");
	
	*ret = *(cpBB*)JS_GetArrayBufferViewData( tmp_arg, cx);
	
	return JS_TRUE;	
}

jsval cpBB_to_jsval(JSContext *cx, cpBB bb )
{
#ifdef __LP64__
	JSObject *typedArray = JS_NewFloat64Array( cx, 4 );
#else
	JSObject *typedArray = JS_NewFloat32Array( cx, 4 );
#endif
	cpBB *buffer = (cpBB*)JS_GetArrayBufferViewData(typedArray, cx);
	
	*buffer = bb;
	return OBJECT_TO_JSVAL(typedArray);
}

JSBool jsval_to_array_of_cpvect( JSContext *cx, jsval vp, cpVect**verts, int *numVerts)
{
	// Parsing sequence
	JSObject *jsobj;
	JSBool ok = JS_ValueToObject( cx, vp, &jsobj );
	JSB_PRECONDITION( ok, "Error converting value to object");
	
	JSB_PRECONDITION( jsobj && JS_IsArrayObject( cx, jsobj),  "Object must be an array");

	uint32_t len;
	JS_GetArrayLength(cx, jsobj, &len);
	
	JSB_PRECONDITION( len%2==0, "Array lenght should be even");
	
	cpVect *array = (cpVect*)malloc( sizeof(cpVect) * len/2);
	
	for( uint32_t i=0; i< len;i++ ) {
		jsval valarg;
		JS_GetElement(cx, jsobj, i, &valarg);

		double value;
		ok = JS_ValueToNumber(cx, valarg, &value);
		JSB_PRECONDITION( ok, "Error converting value to nsobject");
		
		if(i%2==0)
			array[i/2].x = value;
		else
			array[i/2].y = value;
	}
	
	*numVerts = len/2;
	*verts = array;
	
	return JS_TRUE;
}

#pragma mark - Collision Handler

struct collision_handler {
	cpCollisionType		typeA;
	cpCollisionType		typeB;
	jsval				begin;
	jsval				pre;
	jsval				post;
	jsval				separate;
	JSObject			*jsthis;
	JSContext			*cx;

	unsigned long		hash_key;

	unsigned int		is_oo; // Objected oriented API ?
	UT_hash_handle  hh;
};

// hash
struct collision_handler* collision_handler_hash = NULL;

// helper pair
static unsigned long pair_ints( unsigned long A, unsigned long B )
{
	// order is not important
	unsigned long k1 = MIN(A, B );
	unsigned long k2 = MAX(A, B );
	
	return (k1 + k2) * (k1 + k2 + 1) /2 + k2;
}

static cpBool myCollisionBegin(cpArbiter *arb, cpSpace *space, void *data)
{
	struct collision_handler *handler = (struct collision_handler*) data;
	
	jsval args[2];
	if( handler->is_oo ) {
		args[0] = functionclass_to_jsval(handler->cx, arb, JSB_cpArbiter_object, JSB_cpArbiter_class, "cpArbiter");
		args[1] = functionclass_to_jsval(handler->cx, space, JSB_cpSpace_object, JSB_cpSpace_class, "cpArbiter");
	} else {
		args[0] = opaque_to_jsval( handler->cx, arb);
		args[1] = opaque_to_jsval( handler->cx, space );
	}
	
	jsval rval;
	JS_CallFunctionValue( handler->cx, handler->jsthis, handler->begin, 2, args, &rval);
	
	if( JSVAL_IS_BOOLEAN(rval) ) {
		JSBool ret = JSVAL_TO_BOOLEAN(rval);
		return (cpBool)ret;
	}
	return cpTrue;	
}

static cpBool myCollisionPre(cpArbiter *arb, cpSpace *space, void *data)
{
	struct collision_handler *handler = (struct collision_handler*) data;
	
	jsval args[2];
	if( handler->is_oo ) {
		args[0] = functionclass_to_jsval(handler->cx, arb, JSB_cpArbiter_object, JSB_cpArbiter_class, "cpArbiter");
		args[1] = functionclass_to_jsval(handler->cx, space, JSB_cpSpace_object, JSB_cpSpace_class, "cpArbiter");
	} else {
		args[0] = opaque_to_jsval( handler->cx, arb);
		args[1] = opaque_to_jsval( handler->cx, space );
	}
	
	jsval rval;
	JS_CallFunctionValue( handler->cx, handler->jsthis, handler->pre, 2, args, &rval);
	
	if( JSVAL_IS_BOOLEAN(rval) ) {
		JSBool ret = JSVAL_TO_BOOLEAN(rval);
		return (cpBool)ret;
	}
	return cpTrue;	
}

static void myCollisionPost(cpArbiter *arb, cpSpace *space, void *data)
{
	struct collision_handler *handler = (struct collision_handler*) data;
	
	jsval args[2];
	
	if( handler->is_oo ) {
		args[0] = functionclass_to_jsval(handler->cx, arb, JSB_cpArbiter_object, JSB_cpArbiter_class, "cpArbiter");
		args[1] = functionclass_to_jsval(handler->cx, space, JSB_cpSpace_object, JSB_cpSpace_class, "cpArbiter");
	} else {
		args[0] = opaque_to_jsval( handler->cx, arb);
		args[1] = opaque_to_jsval( handler->cx, space );
	}
	
	jsval ignore;
	JS_CallFunctionValue( handler->cx, handler->jsthis, handler->post, 2, args, &ignore);
}

static void myCollisionSeparate(cpArbiter *arb, cpSpace *space, void *data)
{
	struct collision_handler *handler = (struct collision_handler*) data;
	
	jsval args[2];
	if( handler->is_oo ) {
		args[0] = functionclass_to_jsval(handler->cx, arb, JSB_cpArbiter_object, JSB_cpArbiter_class, "cpArbiter");
		args[1] = functionclass_to_jsval(handler->cx, space, JSB_cpSpace_object, JSB_cpSpace_class, "cpArbiter");
	} else {
		args[0] = opaque_to_jsval( handler->cx, arb);
		args[1] = opaque_to_jsval( handler->cx, space );
	}
	
	jsval ignore;
	JS_CallFunctionValue( handler->cx, handler->jsthis, handler->separate, 2, args, &ignore);
}

#pragma mark - cpSpace
#pragma mark addCollisionHandler

static
JSBool __jsb_cpSpace_addCollisionHandler(JSContext *cx, jsval *vp, jsval *argvp, cpSpace *space, unsigned int is_oo)
{
	struct collision_handler *handler = (struct collision_handler*) malloc( sizeof(*handler) );

	JSB_PRECONDITION(handler, "Error allocating memory");
	
	JSBool ok = JS_TRUE;
	
	// args
	ok &= jsval_to_int(cx, *argvp++, (int32_t*) &handler->typeA );
	ok &= jsval_to_int(cx, *argvp++, (int32_t*) &handler->typeB );
	ok &= JS_ValueToObject(cx, *argvp++, &handler->jsthis );
	
	handler->begin =  *argvp++;
	handler->pre = *argvp++;
	handler->post = *argvp++;
	handler->separate = *argvp++;
	
	JSB_PRECONDITION(ok, "Error parsing arguments");
	
	// Object Oriented API ?
	handler->is_oo = is_oo;
	
	if( ! JSVAL_IS_NULL(handler->begin) )
		JS_AddNamedValueRoot(cx, &handler->begin, "begin collision_handler");
	if( ! JSVAL_IS_NULL(handler->pre) )
		JS_AddNamedValueRoot(cx, &handler->pre, "pre collision_handler");
	if( ! JSVAL_IS_NULL(handler->post) )
		JS_AddNamedValueRoot(cx, &handler->post, "post collision_handler");
	if( ! JSVAL_IS_NULL(handler->separate) )
		JS_AddNamedValueRoot(cx, &handler->separate, "separate collision_handler");
	
	handler->cx = cx;
	
	cpSpaceAddCollisionHandler(space, handler->typeA, handler->typeB,
							   JSVAL_IS_NULL(handler->begin) ? NULL : &myCollisionBegin,
							   JSVAL_IS_NULL(handler->pre) ? NULL : &myCollisionPre,
							   JSVAL_IS_NULL(handler->post) ? NULL : &myCollisionPost,
							   JSVAL_IS_NULL(handler->separate) ? NULL : &myCollisionSeparate,
							   handler );
	
	
	//
	// Already added ? If so, remove it.
	// Then add new entry
	//
	struct collision_handler *hashElement = NULL;
	unsigned long paired_key = pair_ints(handler->typeA, handler->typeB );
	HASH_FIND_INT(collision_handler_hash, &paired_key, hashElement);
    if( hashElement ) {
		HASH_DEL( collision_handler_hash, hashElement );
		free( hashElement );
	}
	
	handler->hash_key = paired_key;
	HASH_ADD_INT( collision_handler_hash, hash_key, handler );
	
	
	JS_SET_RVAL(cx, vp, JSVAL_VOID);
	return JS_TRUE;
}

JSBool JSB_cpSpaceAddCollisionHandler(JSContext *cx, uint32_t argc, jsval *vp)
{
	JSB_PRECONDITION( argc==8, "Invalid number of arguments");

	jsval *argvp = JS_ARGV(cx,vp);

	// args
	cpSpace *space;
	JSBool ok = jsval_to_opaque( cx, *argvp++, (void**)&space);
	JSB_PRECONDITION(ok, "Error parsing arguments");
	
	return __jsb_cpSpace_addCollisionHandler(cx, vp, argvp, space, 0);
}

// method
JSBool JSB_cpSpace_addCollisionHandler(JSContext *cx, uint32_t argc, jsval *vp)
{
	JSB_PRECONDITION( argc==7, "Invalid number of arguments");
	JSObject* jsthis = (JSObject *)JS_THIS_OBJECT(cx, vp);
	JSB_PRECONDITION( jsthis, "Invalid jsthis object");
	
	struct jsb_c_proxy_s* proxy = jsb_get_c_proxy_for_jsobject(jsthis);
	void *handle = proxy->handle;
	
	return __jsb_cpSpace_addCollisionHandler(cx, vp, JS_ARGV(cx,vp), (cpSpace*)handle, 1);
}

#pragma mark removeCollisionHandler

static
JSBool __jsb_cpSpace_removeCollisionHandler(JSContext *cx, jsval *vp, jsval *argvp, cpSpace *space)
{
	JSBool ok = JS_TRUE;
	
	cpCollisionType typeA;
	cpCollisionType typeB;
	ok &= jsval_to_int(cx, *argvp++, (int32_t*) &typeA );
	ok &= jsval_to_int(cx, *argvp++, (int32_t*) &typeB );

	JSB_PRECONDITION(ok, "Error parsing arguments");
	
	cpSpaceRemoveCollisionHandler(space, typeA, typeB );
	
	// Remove it
	struct collision_handler *hashElement = NULL;
	unsigned long key = pair_ints(typeA, typeB );
	HASH_FIND_INT(collision_handler_hash, &key, hashElement);
    if( hashElement ) {
		
		// unroot it
		if( ! JSVAL_IS_NULL(hashElement->begin) )
			JS_RemoveValueRoot(cx, &hashElement->begin);
		if( ! JSVAL_IS_NULL(hashElement->pre) )
			JS_RemoveValueRoot(cx, &hashElement->pre);
		if( ! JSVAL_IS_NULL(hashElement->post) )
			JS_RemoveValueRoot(cx, &hashElement->post);
		if( ! JSVAL_IS_NULL(hashElement->separate) )
			JS_RemoveValueRoot(cx, &hashElement->separate);
		
		HASH_DEL( collision_handler_hash, hashElement );
		free( hashElement );
	}
	
	JS_SET_RVAL(cx, vp, JSVAL_VOID);
	return JS_TRUE;
}

// Free function
JSBool JSB_cpSpaceRemoveCollisionHandler(JSContext *cx, uint32_t argc, jsval *vp)
{
	JSB_PRECONDITION( argc==3, "Invalid number of arguments");
	
	jsval *argvp = JS_ARGV(cx,vp);
	
	cpSpace* space;
	JSBool ok = jsval_to_opaque( cx, *argvp++, (void**)&space);
	
	JSB_PRECONDITION(ok, "Error parsing arguments");

	return __jsb_cpSpace_removeCollisionHandler(cx, vp, argvp, space);
}

// method
JSBool JSB_cpSpace_removeCollisionHandler(JSContext *cx, uint32_t argc, jsval *vp)
{
	JSB_PRECONDITION( argc==2, "Invalid number of arguments");
	JSObject* jsthis = (JSObject *)JS_THIS_OBJECT(cx, vp);
	JSB_PRECONDITION( jsthis, "Invalid jsthis object");
	
	struct jsb_c_proxy_s* proxy = jsb_get_c_proxy_for_jsobject(jsthis);
	void *handle = proxy->handle;
	
	return __jsb_cpSpace_removeCollisionHandler(cx, vp, JS_ARGV(cx,vp), (cpSpace*)handle);
}

#pragma mark - Arbiter

#pragma mark getBodies
static
JSBool __jsb_cpArbiter_getBodies(JSContext *cx, jsval *vp, jsval *argvp, cpArbiter *arbiter, unsigned int is_oo)
{
	cpBody *bodyA;
	cpBody *bodyB;
	cpArbiterGetBodies(arbiter, &bodyA, &bodyB);
	
	jsval valA, valB;
	if( is_oo ) {
		valA = functionclass_to_jsval(cx, bodyA, JSB_cpBody_object, JSB_cpBody_class, "cpArbiter");
		valB = functionclass_to_jsval(cx, bodyB, JSB_cpBody_object, JSB_cpBody_class, "cpArbiter");
	} else {
		valA = opaque_to_jsval(cx, bodyA);
		valB = opaque_to_jsval(cx, bodyB);		
	}
	
	JSObject *jsobj = JS_NewArrayObject(cx, 2, NULL);
	JS_SetElement(cx, jsobj, 0, &valA);
	JS_SetElement(cx, jsobj, 1, &valB);
	
	JS_SET_RVAL(cx, vp, OBJECT_TO_JSVAL(jsobj));
	
	return JS_TRUE;	
}

// Free function
JSBool JSB_cpArbiterGetBodies(JSContext *cx, uint32_t argc, jsval *vp)
{
	JSB_PRECONDITION( argc==1, "Invalid number of arguments");
	
	jsval *argvp = JS_ARGV(cx,vp);
	
	cpArbiter* arbiter;
	if( ! jsval_to_opaque( cx, *argvp++, (void**)&arbiter ) )
		return JS_FALSE;

	return __jsb_cpArbiter_getBodies(cx, vp, argvp, arbiter, 0);
}

// Method
JSBool JSB_cpArbiter_getBodies(JSContext *cx, uint32_t argc, jsval *vp)
{
	JSB_PRECONDITION( argc==0, "Invalid number of arguments");
	JSObject* jsthis = (JSObject *)JS_THIS_OBJECT(cx, vp);
	JSB_PRECONDITION( jsthis, "Invalid jsthis object");
	
	struct jsb_c_proxy_s* proxy = jsb_get_c_proxy_for_jsobject(jsthis);
	JSB_PRECONDITION( proxy, "Invalid private object");
	void *handle = proxy->handle;
	
	return __jsb_cpArbiter_getBodies(cx, vp, JS_ARGV(cx,vp), (cpArbiter*)handle, 1);
}

#pragma mark getShapes
static
JSBool __jsb_cpArbiter_getShapes(JSContext *cx, jsval *vp, jsval *argvp, cpArbiter *arbiter, unsigned int is_oo)
{
	cpShape *shapeA;
	cpShape *shapeB;
	cpArbiterGetShapes(arbiter, &shapeA, &shapeB);

	jsval valA, valB;
	if( is_oo ) {
		valA = functionclass_to_jsval(cx, shapeA, JSB_cpShape_object, JSB_cpShape_class, "cpShape");
		valB = functionclass_to_jsval(cx, shapeB, JSB_cpShape_object, JSB_cpShape_class, "cpShape");
	} else {
		valA = opaque_to_jsval(cx, shapeA);
		valB = opaque_to_jsval(cx, shapeB);
	}
	
	JSObject *jsobj = JS_NewArrayObject(cx, 2, NULL);
	JS_SetElement(cx, jsobj, 0, &valA);
	JS_SetElement(cx, jsobj, 1, &valB);
	
	JS_SET_RVAL(cx, vp, OBJECT_TO_JSVAL(jsobj));
	
	return JS_TRUE;
}

// function
JSBool JSB_cpArbiterGetShapes(JSContext *cx, uint32_t argc, jsval *vp)
{
	JSB_PRECONDITION( argc==1, "Invalid number of arguments");
	
	jsval *argvp = JS_ARGV(cx,vp);
	
	cpArbiter* arbiter;
	if( ! jsval_to_opaque( cx, *argvp++, (void**) &arbiter ) )
	   return JS_FALSE;

	return __jsb_cpArbiter_getShapes(cx, vp, argvp, arbiter, 0);
}

// method
JSBool JSB_cpArbiter_getShapes(JSContext *cx, uint32_t argc, jsval *vp)
{
	JSB_PRECONDITION( argc==0, "Invalid number of arguments");
	JSObject* jsthis = (JSObject *)JS_THIS_OBJECT(cx, vp);
	JSB_PRECONDITION( jsthis, "Invalid jsthis object");
	
	struct jsb_c_proxy_s* proxy = jsb_get_c_proxy_for_jsobject(jsthis);
	void *handle = proxy->handle;
	
	return __jsb_cpArbiter_getShapes(cx, vp, JS_ARGV(cx,vp), (cpArbiter*)handle, 1);
}

#pragma mark - Body
#pragma mark getUserData

static
JSBool __jsb_cpBody_getUserData(JSContext *cx, jsval *vp, jsval *argvp, cpBody *body)
{
	JSObject *data = (JSObject*) cpBodyGetUserData(body);
	JS_SET_RVAL(cx, vp, OBJECT_TO_JSVAL(data));
	
	return JS_TRUE;
}

// free function
JSBool JSB_cpBodyGetUserData(JSContext *cx, uint32_t argc, jsval *vp)
{
	JSB_PRECONDITION( argc==1, "Invalid number of arguments");

	jsval *argvp = JS_ARGV(cx,vp);
	cpBody *body;
	if( ! jsval_to_opaque( cx, *argvp++, (void**) &body ) )
		return JS_FALSE;

	return __jsb_cpBody_getUserData(cx, vp, argvp, body);
}

// method
JSBool JSB_cpBody_getUserData(JSContext *cx, uint32_t argc, jsval *vp)
{
	JSB_PRECONDITION( argc==0, "Invalid number of arguments");
	JSObject* jsthis = (JSObject *)JS_THIS_OBJECT(cx, vp);
	JSB_PRECONDITION( jsthis, "Invalid jsthis object");
	
	struct jsb_c_proxy_s* proxy = jsb_get_c_proxy_for_jsobject(jsthis);
	void *handle = proxy->handle;
	
	return __jsb_cpBody_getUserData(cx, vp, JS_ARGV(cx,vp), (cpBody*)handle);
}


#pragma mark setUserData

static
JSBool __jsb_cpBody_setUserData(JSContext *cx, jsval *vp, jsval *argvp, cpBody *body)
{
	JSObject *jsobj;

	JSBool ok = JS_ValueToObject(cx, *argvp++, &jsobj);

	JSB_PRECONDITION(ok, "Error parsing arguments");
	
	cpBodySetUserData(body, jsobj);
	JS_SET_RVAL(cx, vp, JSVAL_VOID);
	
	return JS_TRUE;
}

// free function
JSBool JSB_cpBodySetUserData(JSContext *cx, uint32_t argc, jsval *vp)
{
	JSB_PRECONDITION( argc==2, "Invalid number of arguments");

	jsval *argvp = JS_ARGV(cx,vp);
	cpBody *body;
	JSBool ok = jsval_to_opaque( cx, *argvp++, (void**) &body );
	JSB_PRECONDITION(ok, "Error parsing arguments");
	return __jsb_cpBody_setUserData(cx, vp, argvp, body);
}

// method
JSBool JSB_cpBody_setUserData(JSContext *cx, uint32_t argc, jsval *vp)
{
	JSB_PRECONDITION( argc==1, "Invalid number of arguments");
	JSObject* jsthis = (JSObject *)JS_THIS_OBJECT(cx, vp);
	JSB_PRECONDITION( jsthis, "Invalid jsthis object");
	
	struct jsb_c_proxy_s* proxy = jsb_get_c_proxy_for_jsobject(jsthis);
	void *handle = proxy->handle;
	
	return __jsb_cpBody_setUserData(cx, vp, JS_ARGV(cx,vp), (cpBody*)handle);
}

#pragma mark - Object Oriented Chipmunk

/*
 * Chipmunk Base Object
 */

JSClass* JSB_cpBase_class = NULL;
JSObject* JSB_cpBase_object = NULL;
// Constructor
JSBool JSB_cpBase_constructor(JSContext *cx, uint32_t argc, jsval *vp)
{
	JSB_PRECONDITION( argc==1, "Invalid arguments. Expecting 1");
	
	JSObject *jsobj = JS_NewObject(cx, JSB_cpBase_class, JSB_cpBase_object, NULL);
	
	jsval *argvp = JS_ARGV(cx,vp);
	JSBool ok = JS_TRUE;
	
	void *handle = NULL;
	
	ok = jsval_to_opaque(cx, *argvp++, &handle);
	
	JSB_PRECONDITION(ok, "Error converting arguments for JSB_cpBase_constructor");

	jsb_set_c_proxy_for_jsobject(jsobj, handle, JSB_C_FLAG_DO_NOT_CALL_FREE);
	jsb_set_jsobject_for_proxy(jsobj, handle);
	
	JS_SET_RVAL(cx, vp, OBJECT_TO_JSVAL(jsobj));
	return JS_TRUE;
}

// Destructor
void JSB_cpBase_finalize(JSFreeOp *fop, JSObject *obj)
{
	CCLOGINFO(@"jsbindings: finalizing JS object %p (cpBase)", obj);
	
	// should not delete the handle since it was manually added
}

JSBool JSB_cpBase_getHandle(JSContext *cx, uint32_t argc, jsval *vp)
{
	JSObject* jsthis = (JSObject *)JS_THIS_OBJECT(cx, vp);
	JSB_PRECONDITION( jsthis, "Invalid jsthis object");
	
	struct jsb_c_proxy_s* proxy = jsb_get_c_proxy_for_jsobject(jsthis);
	void *handle = proxy->handle;
	
	jsval ret_val = opaque_to_jsval(cx, handle);
	JS_SET_RVAL(cx, vp, ret_val);
	return JS_TRUE;
}

JSBool JSB_cpBase_setHandle(JSContext *cx, uint32_t argc, jsval *vp)
{
	JSObject* jsthis = (JSObject *)JS_THIS_OBJECT(cx, vp);
	JSB_PRECONDITION( jsthis, "Invalid jsthis object");
	
	JSB_PRECONDITION( argc==1, "Invalid arguments. Expecting 1");
	
	jsval *argvp = JS_ARGV(cx,vp);
	
	void *handle;
	JSBool ok = jsval_to_opaque(cx, *argvp++, &handle);
	JSB_PRECONDITION( ok, "Invalid parsing arguments");

	jsb_set_c_proxy_for_jsobject(jsthis, handle, JSB_C_FLAG_DO_NOT_CALL_FREE);
	jsb_set_jsobject_for_proxy(jsthis, handle);
	
	JS_SET_RVAL(cx, vp, JSVAL_VOID);
	return JS_TRUE;
}


void JSB_cpBase_createClass(JSContext *cx, JSObject* globalObj, const char* name )
{
	JSB_cpBase_class = (JSClass *)calloc(1, sizeof(JSClass));
	JSB_cpBase_class->name = name;
	JSB_cpBase_class->addProperty = JS_PropertyStub;
	JSB_cpBase_class->delProperty = JS_PropertyStub;
	JSB_cpBase_class->getProperty = JS_PropertyStub;
	JSB_cpBase_class->setProperty = JS_StrictPropertyStub;
	JSB_cpBase_class->enumerate = JS_EnumerateStub;
	JSB_cpBase_class->resolve = JS_ResolveStub;
	JSB_cpBase_class->convert = JS_ConvertStub;
	JSB_cpBase_class->finalize = JSB_cpBase_finalize;
	JSB_cpBase_class->flags = JSCLASS_HAS_PRIVATE;
	
	static JSPropertySpec properties[] = {
		{0, 0, 0, 0, 0}
	};
	static JSFunctionSpec funcs[] = {
		JS_FN("getHandle", JSB_cpBase_getHandle, 0, JSPROP_PERMANENT | JSPROP_SHARED | JSPROP_ENUMERATE),
		JS_FN("setHandle", JSB_cpBase_setHandle, 1, JSPROP_PERMANENT | JSPROP_SHARED | JSPROP_ENUMERATE),
		JS_FS_END
	};
	static JSFunctionSpec st_funcs[] = {
		JS_FS_END
	};
	
	JSB_cpBase_object = JS_InitClass(cx, globalObj, NULL, JSB_cpBase_class, JSB_cpBase_constructor,0,properties,funcs,NULL,st_funcs);
}

// Manual "methods"
// Constructor
JSBool JSB_cpPolyShape_constructor(JSContext *cx, uint32_t argc, jsval *vp)
{
	JSB_PRECONDITION(argc==3, "Invalid number of arguments");
	JSObject *jsobj = JS_NewObject(cx, JSB_cpPolyShape_class, JSB_cpPolyShape_object, NULL);
	jsval *argvp = JS_ARGV(cx,vp);
	JSBool ok = JS_TRUE;
	cpBody* body; cpVect *verts; cpVect offset;
	int numVerts;
	
	ok &= jsval_to_functionclass( cx, *argvp++, (void**)&body );
	ok &= jsval_to_array_of_cpvect( cx, *argvp++, &verts, &numVerts);
	ok &= jsval_to_cpVect( cx, *argvp++, (cpVect*) &offset );
	JSB_PRECONDITION(ok, "Error processing arguments");
	cpShape *shape = cpPolyShapeNew(body, numVerts, verts, offset);

	jsb_set_c_proxy_for_jsobject(jsobj, shape, JSB_C_FLAG_DO_NOT_CALL_FREE);
	jsb_set_jsobject_for_proxy(jsobj, shape);
	
	JS_SET_RVAL(cx, vp, OBJECT_TO_JSVAL(jsobj));
	
	free(verts);
	
	return JS_TRUE;
}

#endif // JSB_INCLUDE_CHIPMUNK
