//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Structs handling packing of smaller virtual textures onto larger physical textures.
module demo.texturepacker;


import std.stdio;

import util.linalg;


/// Binary tree based texture packer. Handles allocation of texture page space.
/// 
/// Texture space is subdivided vertically/horizontally to pack multiple smaller
/// logical textures into a larger physical texture.
struct BinaryTexturePacker 
{
private:
    // Node representing a rectangular area on the texture.
    //
    // A node is either a leaf (which might or might not be allocated),
    // or it has two children which might or might not be leaves.
    struct Node
    {
    public:
        // Minimum (inclusive) bounds of the pixel area managed by the node.
        vec2us min;
        // Maximum (exclusive) bounds of the pixel area managed by the node.
        vec2us max;
    private:
        // Index of this node in nodeStorage_.
        ushort id_;
        // Index of the first child in nodeStorage_.
        ushort childA_ = ushort.max;
        // Index of the second child in nodeStorage_.
        ushort childB_ = ushort.max;
        // Is this node's area taken up?
        bool full_ = false;

    public:
        // Construct a Node with specified ID, minimum and maximum bounds.
        this(const ushort id, const vec2us min, const vec2us max) @safe pure nothrow
        {
            this.id_ = id;
            this.min = min;
            this.max = max;
        }

        // Try to allocate a rectangular area with specified size.
        //
        // Params: size   = Size of the area in pixels.
        //         packer = BinaryTexturePacker owning this node.
        //
        // Returns: ID (nodeStorage_ index) of the inserted node on success, 
        //          ushort.max on failure.
        ushort allocate(const vec2us size, ref BinaryTexturePacker packer) @safe
        {
            assert(size != vec2us(cast(ushort)0, cast(ushort)0),
                   "Can't pack a zero sized image");

            // Not a leaf.
            if(childA_ != ushort.max && childB_ != ushort.max)
            {
                // Try inserting to the first child.
                const inserted = packer.nodeStorage_[childA_].allocate(size, packer);
                // If there's no room, try the second 
                // (if that fails as well, will return ushort.max).
                return inserted == ushort.max 
                       ? packer.nodeStorage_[childB_].allocate(size, packer)
                       : inserted;
            }
            // Already taken, can't allocate here.
            if(full_){return ushort.max;}
            // Can't store more nodes since we're using ushorts for indexing.
            if(packer.nodeStorage_.length >= ushort.max){return ushort.max;}

            const areaSize = vec2us(cast(ushort)(max.x - min.x), cast(ushort)(max.y - min.y));
            // If this node is too small:
            if(areaSize.x < size.x || areaSize.y < size.y){return ushort.max;}
            // If exact fit, use this node.
            if(areaSize == size)
            {
                full_ = true;
                return id_;
            }

            with(packer)
            {
                // The children's areas will be changed in following code.
                childA_ = cast(ushort)nodeStorage_.length;
                nodeStorage_ ~= Node(childA_, min, max);
                childB_ = cast(ushort)nodeStorage_.length;
                nodeStorage_ ~= Node(childB_, min, max);

                // Decide which way to split.
                const vec2us freeSpace = vec2us(cast(ushort)(areaSize.x - size.x),
                                                cast(ushort)(areaSize.y - size.y));
                // Split with a vertical cut if more free space to the right.
                if(freeSpace.x > freeSpace.y)
                {
                    nodeStorage_[childA_].max.x = cast(ushort)(min.x + size.x);
                    nodeStorage_[childB_].min.x = cast(ushort)(min.x + size.x);
                }
                // Split with a horizontal cut if more free space to the bottom.
                else
                {
                    nodeStorage_[childA_].max.y = cast(ushort)(min.y + size.y);
                    nodeStorage_[childB_].min.y = cast(ushort)(min.y + size.y);
                }
                return nodeStorage_[childA_].allocate(size, packer);
            }
        }

        // Free the area taken up by this node.
        //
        // Params:  area = Area this node is expected to take up, for error checking.
        void free(ref const TextureArea area) @safe pure nothrow
        {
            assert(area.min == min && area.max == max && full_,
                   "Texture packer area being removed doesn't match its ID");
            assert(childA_ == ushort.max && childB_ == ushort.max,
                   "Area node we're freeing is not a leaf - "
                   "it should not have been used in the first place");
            full_ = false;
        }

        // Is this node completely empty (i.e. no space within is allocated)?
        bool empty(ref const BinaryTexturePacker packer) @safe const pure nothrow
        {
            return !full_ &&
                   (childA_ == ushort.max || packer.nodeStorage_[childA_].empty(packer)) &&
                   (childB_ == ushort.max || packer.nodeStorage_[childB_].empty(packer));
        }
    }

    import containers.vector;
    alias containers.vector.Vector Vector;

    // Stores area nodes. The root node is at index 0.
    Vector!Node nodeStorage_;

    // Size of texture space managed by this packer, in pixels.
    vec2us size_;

public:
    /// Construct a BinaryTexturePacker
    ///
    /// Params:  size = Size of texture space for the packer to manage.
    this(const vec2us size)
    {
        size_ = size;
        nodeStorage_ ~= Node(0, vec2us(cast(ushort)0, cast(ushort)0), size);
    }

    /// Free specified page area.
    ///
    /// Params:  area = Page area to free. Must be a value previously returned by
    ///                 allocateSpace() of the same BinaryTexturePacker instance.
    void freeSpace(ref const TextureArea area) @safe pure nothrow
    {
        nodeStorage_[area.id_].free(area);
    }

    /// Try to allocate texture space with specified size.
    ///
    /// Params:  size = Size of texture space to allocate, in pixels.
    ///
    /// Returns: Allocated texture area on success, invalid texture area on failure.
    TextureArea allocateSpace(const vec2us size)
    {
        ushort id = nodeStorage_[0].allocate(size, this);
        // ushort.max is failed allocation - will result in an invalid TextureArea.
        return id == ushort.max ? TextureArea(id)
                                : TextureArea(id, nodeStorage_[id].min, nodeStorage_[id].max);
    }

    /// Is this BinaryTexturePacker completely empty?
    @property bool empty() @safe const pure nothrow 
    {
        return nodeStorage_[0].empty(this);
    }
}
unittest 
{
    writeln("BinaryTexturePacker unittest");

    // Construction
    auto packer = BinaryTexturePacker(vec2us(cast(ushort)64, cast(ushort)64));
    assert(packer.empty);

    // Inserting
    const area1 = packer.allocateSpace(vec2us(cast(ushort)64, cast(ushort)32));
    assert(!packer.empty);
    assert(area1.id_ == 1);
    const area2 = packer.allocateSpace(vec2us(cast(ushort)32, cast(ushort)32));
    assert(area2.id_ == 3);
    const area3 = packer.allocateSpace(vec2us(cast(ushort)32, cast(ushort)32));
    assert(area3.id_ == 4);

    // Out of space
    const area4 = packer.allocateSpace(vec2us(cast(ushort)1, cast(ushort)1));
    assert(area4.id_ == ushort.max && !area4.valid);


    // Freeing & reinserting same size
    packer.freeSpace(area3);
    const area5 = packer.allocateSpace(vec2us(cast(ushort)32, cast(ushort)32));
    assert(area3 == area5);
    const area6 = packer.allocateSpace(vec2us(cast(ushort)1, cast(ushort)1));
    assert(area6.id_ == ushort.max && !area6.valid);

    // Freeing and reinserting smaller areas
    packer.freeSpace(area5);
    const area7  = packer.allocateSpace(vec2us(cast(ushort)16, cast(ushort)32));
    const area8  = packer.allocateSpace(vec2us(cast(ushort)8, cast(ushort)32));
    const area9  = packer.allocateSpace(vec2us(cast(ushort)8, cast(ushort)8));
    const area10 = packer.allocateSpace(vec2us(cast(ushort)9, cast(ushort)32));
    assert(area10.id_ == ushort.max && !area10.valid);

    // Freeing everything
    packer.freeSpace(area1);
    packer.freeSpace(area2);
    packer.freeSpace(area7);
    packer.freeSpace(area8);
    packer.freeSpace(area9);
    assert(packer.empty);
}

/// Area of texture space allocated by a texture packer.
///
/// Used for virtual textures packed into a larger physical texture.
struct TextureArea
{
private:
    // ID of the texture area used by the texture packer. ushort.max means invalid.
    ushort id_ = ushort.max;

    // Minimum (inclusive) extents of the texture space (in pixels).
    vec2us min_;

    // Maximum (exclusive) extents of the texture space (in pixels).
    vec2us max_;

public:
    /// Is this texture area valid (successfully allocated)?
    ///
    /// Invalid texture areas should never be used; instead, a different
    /// texture / texture packer should be used to allocate a new area.
    @property bool valid() @safe const pure nothrow {return id_ != ushort.max;}

    /// Minimum (inclusive) extents of the texture space (in pixels).
    @property vec2u min() @safe const pure nothrow {return vec2u(min_.x, min_.y);}

    /// Maximum (exclusive) extents of the texture space (in pixels).
    @property vec2u max() @safe const pure nothrow {return vec2u(max_.x, max_.y);}
}
