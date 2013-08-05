//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Manages a square area of space by recursively subdividing it into half-sizes quads.
module spatial.quadtree;

import std.array;
import std.exception;
import std.math;
import std.stdio;
import std.typecons;

import spatial.boundingsphere;
import spatial.centeredsquare;
import spatial.spatialmanager;
import util.linalg;

/// Manages a square area of space by recursively subdividing it into half-sizes quads.
///
/// Supports logarithmic object insertion and removal and iteration over objects in 
/// an area.
///
/// Params: T = Type stored in the QuadTree. Must define the following functions:
///             vec3 position()
///             BoundingSphere boundingSphere()
struct QuadTree(T)
{
private:
    // Root node of the quad tree.
    QuadNode!T root_;

    // Square representing the managed area.
    CenteredSquare rootSquare_;

    // Objects outside the area managed by the quadtree.
    T*[] outerObjects_;

    @disable this(this);

public:
    /// Construct a QuadTree.
    ///
    /// Params:  quadTreeSquare       = Square representing the area of 
    ///                                 space managed by this quadtree.
    ///          targetObjectsPerNode = Number of objects to store in a node 
    ///                                 of the quadtree before triggering 
    ///                                 subdivision.
    ///                                 (Note that there still might be more 
    ///                                 objects in a node if they don't fit 
    ///                                 into any of the child nodes).
    this(const CenteredSquare quadTreeSquare, const uint targetObjectsPerNode)
        @safe pure nothrow
    {
        rootSquare_      = quadTreeSquare;
        root_.fullLimit_ = targetObjectsPerNode;
    }

    /// Get a string representation of the quadtree.
    string toString()
    {
        return root_.toString();
    }

    /// Insert a new object to the quadtree.
    ///
    /// The position or bounds of the object must not be modified
    /// before a corresponding call to removeObject().
    ///
    /// Complexity: O(log(objectsInQuadTree))
    void insertObject(T* object) @safe
    {
        if(objectFitsInNode(object, rootSquare_))
        {
            root_.insert(object, rootSquare_);
            return;
        }
        outerObjects_ ~= object;
    }

    /// Remove an object from the quadtree.
    ///
    /// The position and bounds of the objects must be the same as they were
    /// when it was inserted.
    ///
    /// The object must be in the quadtree.
    ///
    /// Complexity: O(log(objectsInQuadTree)), falling back to O(objectsInQuadTree)
    ///             if a rounding error triggers a full tree search.
    void removeObject(const(T)* object) @trusted
    {
        try
        {
            if(objectFitsInNode(object, rootSquare_))
            {
                root_.remove(object, rootSquare_);
                return;
            }
            else if(!removeObjectFromArray(object, outerObjects_))
            {
                throw new SpatialNotFoundException 
                    ("Object to be removed from a QuadTree was not " ~
                     "found. Object data:\n " ~ to!string(*object));
            }
        }
        catch(SpatialNotFoundException e)
        {
            // This can only happen due to caller error (which needs to be fixed)
            // or a rare float precision error.
            writeln("WARNING: Fast object removal from a QuadTree failed. ",
                    "Doing a forced removal.");
            if(root_.forceRemove(object, rootSquare_))
            {
                return;
            }
            else if(!removeObjectFromArray(object, outerObjects_))
            {
                assert(false, "Force-removing an object from a spatial manager failed. " ~
                              "Maybe double-removing?");
            }
        }
    }

    /// Get a foreachable iterator over all objects in specified area in the QuadTree.
    ///
    /// Params:  square   = Objects intersecting this area will be iterated over.
    auto objectsInSquare(const CenteredSquare square)
    {
        // Range (iterator) to iterate over all objects in a square area in the QuadTree.
        static struct ObjectsInArea
        {
        private:
            // QuadTree we are iterating over.
            QuadTree* qTree_;

            // Bounds of the area to iterate over.
            CenteredSquare boundsSquare_;

        public:
            @disable this(this);

            // Foreach over all objects in the tree within specified bounds.
            int opApply(int delegate(T*) dg)
            {
                int result = 0;

                // Objects outside the quadtree
                //
                // We need to always consider these, as an object might be intersecting
                // the border of the quadtree or large enough to span the entire quad tree.
                // In such cases, even if boundsSquare is within the quadtree, it might 
                // intersect some of the outer objects.
                foreach(object; qTree_.outerObjects_)
                {
                    // Still need to check if they intersect with the square.
                    const objectSquare = 
                        CenteredSquare((object.position + object.boundingSphere.center).xy, 
                                       object.boundingSphere.radius);
                    if(!boundsSquare_.intersects(objectSquare))
                    {
                        continue;
                    }
                    result = dg(object);
                    if(result){break;}
                }

                // Objects inside the quadtree.
                if(boundsSquare_.intersects(qTree_.rootSquare_))
                {
                    foreach(T* object;
                            qTree_.root_.objectsInSquare(boundsSquare_, qTree_.rootSquare_))
                    {
                        // Quadtree nodes have already ensured that all objects iterated
                        // do intersect with the square.
                        result = dg(object);
                        if(result){break;}
                    }
                }

                return result;
            }
        }

        return ObjectsInArea(&this, square);
    }
}

private:
// Single node of a quadtree storing objects of type T.
//
// Manages a square area, possibly subdivided into 4 square child nodes.
// All objects in the node are fully contained by its area. Even if subdivided 
// into children, only objects small enough to fit are inserted into the children.
//
// Area of the node is inferred from the area of the quadtree, calculated during 
// recursive insert/remove operations. It might be moved to a data member later.
struct QuadNode(T)
{
private:
    // Objects within this node. All objects within a node are fully contained by the node.
    //
    // We try subdivide if there are more objects than fullLimit_, but if they don't fit 
    // into the children, they stay here so we don't have the same object in multiple children.
    T*[] objects_;

    // Child nodes, if any. Either null or 4 nodes.
    //
    // The order of the children is: NE/SE/SW/NW,
    // where high Y values are N, low Y is S, high X is E and low X is W.
    QuadNode[] children_ = null;

    // Maximum objects before triggering a subdivision.
    //
    // There might still be more objects in a node if they don't fit into 
    // any of the child nodes.
    uint fullLimit_ = 0;

public:
    // Insert an object into this node.
    //
    // If there are too many objects in the node, it will be inserted into
    // children (subdividing into children if this is a leaf node).
    //
    // Params:  object   = Object to insert.  nodeArea = Spatial area of this
    // node.
    void insert(T* objectToInsert, const CenteredSquare nodeArea) @trusted
    { assert(fullLimit_ > 0, "QuadNode with a zero (uninitialized?)
            fullLimit_"); assert(objectFitsInNode(objectToInsert, nodeArea),
        "Can't call insert with an object that doesn't fit into this node.");

        // Subdivide a leaf if full.
        if(full && leaf)
        {
            // Possible optimization: Use a 4-slice to an array in QuadTree.
            children_ = new QuadNode[4];
            foreach(ref child; children_) {child.fullLimit_ = fullLimit_;}
            // New size of objects_ after we've moved everything we could into children.
            uint newObjectCount = 0;
            foreach(object; objects_)
            {
                if(!insertToAnyChild(object, nodeArea))
                {
                    objects_[newObjectCount] = object;
                    ++newObjectCount;
                }
            }
            objects_ = objects_[0 .. newObjectCount];
            // Allow GC to reuse allocated storage.
            objects_.assumeSafeAppend();
        }

        // If not a leaf, insert into children.
        // Will fail if it's too big for any child.
        if(!leaf && insertToAnyChild(objectToInsert, nodeArea))
        {
            return;
        }

        // Not full, or the object was too big for any child.
        objects_ ~= objectToInsert;
        objects_.assumeSafeAppend();
    }

    // Remove an object from this node.
    //
    // Params:  object   = Object to remove.
    //          nodeArea = Spatial area of this node.
    //
    // Throws:  SpatialNotFoundException if the object is not found in the node or its children.
    void remove(const(T)* object, const CenteredSquare nodeArea)
    {
        if(!leaf && actOnChild(&removeFromChild, object, nodeArea))
        {
            return;
        }

        enforce(removeObjectFromArray(object, objects_),
                new SpatialNotFoundException 
                    ("Object to be removed from a QuadTree was not " ~
                     "found. Object data:\n " ~ to!string(*object)));
    }

    // Force-remove an object from this node, exhaustively searching all children.
    //
    // Params:  object   = Object to remove.
    //          nodeArea = Spatial area of this node.
    //
    // Returns: true if the object was successfully removed. False otherwise.
    bool forceRemove(const(T)* object, const CenteredSquare nodeArea)
    {
        if(removeObjectFromArray(object, objects_))
        {
            return true;
        }
        // It wasn't here, and we have no children.
        else if(leaf)
        {
            return false;
        }

        const childHSize = nodeArea.halfSize * 0.5f;
        foreach(c, offset; tuple(vec2( childHSize,  childHSize),
                                 vec2( childHSize, -childHSize),
                                 vec2(-childHSize, -childHSize),
                                 vec2(-childHSize,  childHSize)))
        {
            const childArea = CenteredSquare(nodeArea.center + offset, childHSize);
            auto child = &(children_[c]);
            if(child.forceRemove(object, nodeArea))
            {
                return true;
            }
        }
        return false;
    }

    // Get a string representation of this node.
    string toString()
    {
        return recursiveToString(0);
    }

private:
    // Recursively create a string representation of this node and its children.
    //
    // Used for debugging.
    //
    // Params:  indentLevel = Indentation level used to mark nesting of the node.
    string recursiveToString(uint indentLevel)
    {
        string indent;
        foreach(i; 0 .. indentLevel) {indent ~= " ";}
        string result;
        foreach(object; objects_)
        {
            result ~= indent ~ to!string(object.boundingSphere) ~ ", "
                             ~ to!string(object.position) ~ "\n";
        }
        foreach(ref child; children_)
        {
            result ~= child.recursiveToString(indentLevel + 4);
        }
        result ~= indent ~ to!string(fullLimit_) ~ "\n";
        return result;
    }

    // Is this node full (does it have more or as many objects as is the limit) ?
    @property bool full() @safe const pure nothrow {return objects_.length >= fullLimit_;}

    // Is this node a leaf (no children)?
    @property bool leaf() @safe const pure nothrow 
    {
        assert(children_.empty || children_.length == 4, 
               "Invalid number of children for a quad node");
        return children_ is null;
    }

    // Insert an object to any child of this node that can fully contain it.
    //
    // Params:  object   = Object to insert.
    //          nodeArea = Spatial area of this node.
    //
    // Returns:  true of there is a child that can fully contain the object
    //           and the object was inserted, false otherwise.
    bool insertToAnyChild(T* object, const CenteredSquare nodeArea)
        @safe
    {
        return actOnChild(&insertToChild, object, nodeArea);
    }

    // If a child exists that fully contains the object, calls specified delegate.
    //
    // Params: act      = Function to call 
    //                    (with child index, object and child area as parameters).
    //         object   = Object to pass to the function.
    //         nodeArea = Spatial area of this node.
    //
    // Returns:  true if any child was found that fully contained the object 
    //           (and act was called), false otherwise.
    bool actOnChild(TPtr)(void delegate(const size_t, TPtr, const CenteredSquare) act,
                          TPtr object, const CenteredSquare nodeArea) @trusted
    {
        assert(!leaf, "actOnChild called for a leaf node");
        CenteredSquare childArea;
        childArea.halfSize = 0.5f * nodeArea.halfSize;
        childArea.center   = nodeArea.center;
        const pos = object.position + object.boundingSphere.center;
        uint childIndex;

        // NE
        if     (pos.x >= nodeArea.center.x && pos.y >= nodeArea.center.y)
        {
            childArea.center += vec2(childArea.halfSize, childArea.halfSize);
            childIndex  = 0;
        }
        // SE
        else if(pos.x >= nodeArea.center.x && pos.y < nodeArea.center.y)
        {
            childArea.center += vec2(childArea.halfSize, -childArea.halfSize);
            childIndex  = 1;
        }
        // NW
        else if(pos.x < nodeArea.center.x  && pos.y >= nodeArea.center.y)
        {
            childArea.center += vec2(-childArea.halfSize, childArea.halfSize);
            childIndex  = 3;
        }
        // SW
        else if(pos.x < nodeArea.center.x  && pos.y < nodeArea.center.y)
        {
            childArea.center += vec2(-childArea.halfSize, -childArea.halfSize);
            childIndex  = 2;
        }
        else{assert(false, "This line should never be reached");}

        if(objectFitsInNode(object, childArea))
        {
            act(childIndex, object, childArea);
            return true;
        }
        return false;
    }

    // Insert an object into a child node.
    //
    // Params:  childIndex = Index of the child to insert into.
    ///         object     = Object to inset.
    //          childArea  = Spatial area of the child.
    void insertToChild(const size_t childIndex, T* object,
                       const CenteredSquare childArea)
    {
        assert(!leaf, "Can't insert to child with a leaf node");
        children_[childIndex].insert(object, childArea);
    }

    // Remove an object from a child node.
    //
    // Params:  childIndex = Index of the child to remove from.
    ///         object     = Object to remove.
    //          childArea  = Spatial area of the child.
    void removeFromChild(const size_t childIndex, const(T)* object,
                         const CenteredSquare childArea)
    {
        assert(!leaf, "Can't insert to child with a leaf node");
        children_[childIndex].remove(object, childArea);
    }

    // Get a foreachable iterator over all objects in specified area in this node.
    //
    // Params:  square   = Objects intersecting this area will be iterated over.
    //          nodeArea = Area of this node.
    ObjectRangeQuad!T objectsInSquare(const CenteredSquare square, 
                                      const CenteredSquare nodeArea)
    {
        return ObjectRangeQuad!T(&this, square, nodeArea);
    }
}

// Range (iterator) to iterate over all objects in a square area in a node and its children.
struct ObjectRangeQuad(T)
{
private:
    // Node to iterate over.
    QuadNode!T* node_;

    // Bounds of the area to iterate over.
    CenteredSquare boundSquare_;

    // Bounds of the node.
    CenteredSquare nodeSquare_;

public:
    @disable this(this);

    // Foreach over all objects in this node within specified bounds.
    int opApply(int delegate(T*) dg)
    {
        int result = 0;

        // Objects stored directly in this node.
        foreach(object; node_.objects_)
        {
            const objectSquare = 
                CenteredSquare((object.position + object.boundingSphere.center).xy, 
                               object.boundingSphere.radius);
            if(!boundSquare_.intersects(objectSquare))
            {
                continue;
            }
            result = dg(object);
            if(result){break;}
        }

        if(node_.leaf) {return result;}

        const childHSize = 0.5f * nodeSquare_.halfSize;
        // Iterate over objects in children.
        foreach(c, offset; tuple(vec2( childHSize,  childHSize),
                                 vec2( childHSize, -childHSize),
                                 vec2(-childHSize, -childHSize),
                                 vec2(-childHSize,  childHSize)))
        {
            const childArea = CenteredSquare(nodeSquare_.center + offset, childHSize);
            if(boundSquare_.intersects(childArea))
            {
                auto child = &(node_.children_[c]);
                foreach(T* object; child.objectsInSquare(boundSquare_, childArea))
                {
                    result = dg(object);
                    if(result){break;}
                }
            }
        }
        return result;
    }
}

// Determine if specified object (with a bounding sphere) fits into a quadtree 
// node with specified square area.
//
// Params:   object   = Object to test.
//           nodeArea = Area of the node to test object fit with.
//
// Returns:  true if the object fits, false otherwise.
bool objectFitsInNode(T)(const(T)* object, const CenteredSquare nodeArea)
    @safe pure nothrow
{
    const sphere = object.boundingSphere;
    return nodeArea.contains(CenteredSquare(object.position.xy +
                                            sphere.center.xy, sphere.radius));
}

// Remove specified object from an array, using pointer identity (is).
//
// The array will be modified and no other
// slices to it should exist before this call.
// If the object is not present in the array,
// a SpatialNotFoundException will be thrown.
//
// Params:  object = Pointer to the object to remove.
//          array  = Array to remove from.
//
// Returns: true if the object was found and removed, false otherwise.
bool removeObjectFromArray(T)(const(T)* object, ref T*[] array) @trusted
{
    size_t newLength = 0;
    foreach(obj; array)
    {
        if(obj is object) {continue;}
        array[newLength] = obj; 
        ++newLength;
    }
    if(newLength == array.length)
    {
        return false;
    }
    array = array[0 .. newLength];
    array.assumeSafeAppend();
    return true;
}

unittest
{
    struct TestObject
    {
        BoundingSphere boundingSphere;
        vec3 position;
    }

    auto testObject1 = TestObject(BoundingSphere(vec3(16, 16, 0), 17.0f));
    testObject1.position = vec3(0, 0, 0);
    assert(objectFitsInNode(&testObject1,  CenteredSquare(vec2(0, 0), 34)));
    assert(!objectFitsInNode(&testObject1, CenteredSquare(vec2(0, 0), 33)));
    assert(!objectFitsInNode(&testObject1, CenteredSquare(vec2(16, 16), 6)));
    assert(objectFitsInNode(&testObject1,  CenteredSquare(vec2(16, 16), 18)));
    assert(!objectFitsInNode(&testObject1, CenteredSquare(vec2(12, 12), 17)));
    testObject1.position = vec3(-4, -4, 0);
    assert(objectFitsInNode(&testObject1,  CenteredSquare(vec2(0, 0), 30)));
    assert(!objectFitsInNode(&testObject1, CenteredSquare(vec2(0, 0), 29)));
    assert(!objectFitsInNode(&testObject1, CenteredSquare(vec2(12, 12), 6)));
    assert(objectFitsInNode(&testObject1,  CenteredSquare(vec2(12, 12), 18)));
    assert(!objectFitsInNode(&testObject1, CenteredSquare(vec2(12, 12), 17)));


    auto qTree = QuadTree!TestObject(CenteredSquare(vec2(16, 16), 256.0f), 2);

    // ---------------------
    // Test object insertion
    // ---------------------


    // Can't be fit into any children of root (in center)
    qTree.insertObject(&testObject1);
    assert(qTree.rootSquare_.center    == vec2(16, 16));
    assert(qTree.rootSquare_.halfSize  == 256.0f);
    assert(qTree.root_.objects_.length == 1);
    assert(qTree.root_.objects_[0]     is &testObject1);
    assert(qTree.root_.children_       is null);
    assert(qTree.root_.fullLimit_      == 2);

    // After root_ is full, this will go into the NE child
    auto testObject2 = TestObject(BoundingSphere(vec3(0, 0, 0), 7.0f));
    testObject2.position = vec3(64, 64, 0);
    qTree.insertObject(&testObject2);
    assert(qTree.root_.objects_.length == 2);
    assert(qTree.root_.objects_[1]     is &testObject2);
    assert(qTree.root_.children_       is null);

    // After root_ is full, this will go into the SW child
    auto testObject3 = TestObject(BoundingSphere(vec3(0, 0, 0), 7.0f));
    testObject3.position = vec3(-64, -64, 0);
    qTree.insertObject(&testObject3);
    assert(qTree.root_.objects_.length  == 1);
    assert(qTree.root_.objects_[0]      == &testObject1);
    assert(qTree.root_.children_.length == 4);
    assert(qTree.root_.fullLimit_       == 2);
    assert(qTree.root_.children_[0].objects_.length == 1);
    assert(qTree.root_.children_[0].objects_[0]     is &testObject2);
    assert(qTree.root_.children_[0].children_       is null);
    assert(qTree.root_.children_[0].fullLimit_      == 2);

    assert(qTree.root_.children_[1].objects_.length == 0);
    assert(qTree.root_.children_[1].children_       is null);
    assert(qTree.root_.children_[1].fullLimit_      == 2);

    assert(qTree.root_.children_[2].objects_.length == 1);
    assert(qTree.root_.children_[2].objects_[0]     is &testObject3);
    assert(qTree.root_.children_[2].children_       is null);
    assert(qTree.root_.children_[2].fullLimit_      == 2);

    assert(qTree.root_.children_[3].objects_.length == 0);
    assert(qTree.root_.children_[3].children_       is null);
    assert(qTree.root_.children_[3].fullLimit_      == 2);


    // ------------------
    // Test object access
    // ------------------
    auto testCenter      = vec2(64, 64);
    auto testHalfSize    = 48;
    auto expectedObjects = [&testObject1, &testObject2, &testObject3];
    uint i = 0;
    foreach(object; qTree.objectsInSquare(CenteredSquare(testCenter, testHalfSize)))
    {
        assert(object is expectedObjects[i]);
        ++i;
    }

    testHalfSize    = 1;
    expectedObjects = [&testObject2];
    i = 0;
    foreach(object; qTree.objectsInSquare(CenteredSquare(testCenter, testHalfSize)))
    {
        assert(object is expectedObjects[i]);
        ++i;
    }

    auto testObject4 = TestObject(BoundingSphere(vec3(0, 0, 0), 24.0f), vec3(50.0f, 70.0f));
    auto testObject5 = TestObject(BoundingSphere(vec3(0, 0, 0), 24.0f), vec3(70.0f, 50.0f));
    auto testObject6 = TestObject(BoundingSphere(vec3(0, 0, 0), 24.0f), vec3(50.0f, 50.0f));
    auto testObject7 = TestObject(BoundingSphere(vec3(0, 0, 0), 24.0f), vec3(70.0f, 70.0f));
    qTree.insertObject(&testObject4);
    qTree.insertObject(&testObject5);
    qTree.insertObject(&testObject6);
    qTree.insertObject(&testObject7);


    testCenter   = vec2(64, 64);
    testHalfSize = 1;
    bool[5] foundObjects;
    foreach(object; qTree.objectsInSquare(CenteredSquare(testCenter, testHalfSize)))
    {
        if(object is &testObject2)     {assert(foundObjects[0] == false); foundObjects[0] = true;}
        else if(object is &testObject4){assert(foundObjects[1] == false); foundObjects[1] = true;}
        else if(object is &testObject5){assert(foundObjects[2] == false); foundObjects[2] = true;}
        else if(object is &testObject6){assert(foundObjects[3] == false); foundObjects[3] = true;}
        else if(object is &testObject7){assert(foundObjects[4] == false); foundObjects[4] = true;}
        else{assert(false);}
    }
    foreach(found; foundObjects) {assert(found == true);}

    foundObjects[] = false;
    testCenter     = vec2(96, 96);
    testHalfSize   = 15;
    foreach(object; qTree.objectsInSquare(CenteredSquare(testCenter, testHalfSize)))
    {
        if(object is &testObject7){assert(foundObjects[0] == false); foundObjects[0] = true;}
        else{assert(false, to!string(*object));}
    }
    foreach(found; foundObjects[0 .. 1]) {assert(found == true);}


    // Removing stuff
    qTree.removeObject(&testObject7);
    foreach(object; qTree.objectsInSquare(CenteredSquare(testCenter, testHalfSize)))
    {
        assert(false, "TODO");
    }

    qTree.removeObject(&testObject2);

    testCenter   = vec2(64, 64);
    testHalfSize = 1;
    foundObjects[] = false;
    foreach(object; qTree.objectsInSquare(CenteredSquare(testCenter, testHalfSize)))
    {
        if     (object is &testObject4){assert(foundObjects[0] == false); foundObjects[0] = true;}
        else if(object is &testObject5){assert(foundObjects[1] == false); foundObjects[1] = true;}
        else if(object is &testObject6){assert(foundObjects[2] == false); foundObjects[2] = true;}
        else{assert(false);}
    }
    foreach(found; foundObjects[0 .. 3]) {assert(found == true);}
}
