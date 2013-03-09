//          Copyright Ferdinand Majerech 2012.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Code related to vertex attributes.
module video.vertexattribute;


import std.traits;

import gl3n.linalg;

import video.limits;


/// Vertex attribute data types.
enum AttributeType : ubyte
{
   /// 4D float vector.
   vec4 = 0,
   /// 3D float vector.
   vec3 = 1,
   /// 2D float vector.
   vec2 = 2
}

/// Interpretation of a vertex attribute in shader.
///
/// Name of an interpretation value matches the name of the vertex attribute in
/// shader.
enum AttributeInterpretation : ubyte
{
    /// Vertex position.
    Position = 0,
    /// Vertex color.
    Color    = 1,
    /// Vertex normal.
    Normal   = 2,
    /// Texture coordinate.
    TexCoord = 3
}

/// Names of attribute interpretations used in shaders.
///
/// This should be used instead of to!string to avoid allocations.
enum string[(EnumMembers!AttributeInterpretation).length] attributeInterpretationNames =
  ["Position", "Color", "Normal", "TexCoord"];

/// Specifies a single vertex attribute.
struct VertexAttribute
{
    /// Data type of the attribute.
    AttributeType type;
    /// Interpretation of the attribute.
    AttributeInterpretation interpretation;

    /// Construct a vertex attribute with specified type and interpretation.
    this(const AttributeType type,
         const AttributeInterpretation interpretation) @safe pure nothrow
    {
        this.type           = type;
        this.interpretation = interpretation;
    }
}

/// Specification of all attributes in a vertex.
///
/// Mixed in into a vertex by the VertexAttribute template.
struct VertexAttributeSpec
{
private:
    /// Stores attribute definitions.
    VertexAttribute[MAX_ATTRIBUTES] attributesStorage_;

public:
    /// Attribute definitions. Slice into attributesStorage_.
    VertexAttribute[] attributes;

    /// Construct a VertexAttributeSpec with specified attributes.
    this(VertexAttribute[] attributesArg)
    {
        assert(attributesArg.length < attributesStorage_.length, 
               "Too many vertex attributes");
        attributesStorage_[0 .. attributesArg.length] = attributesArg[];
        this.attributes = attributesStorage_[0 .. attributesArg.length];
    }

    /// Determine if the specification is valid (using asserts).
    void validate() @safe pure nothrow
    {
        // There can be at most one attribute of every interpretation,
        // and position is required.
        uint[(EnumMembers!AttributeInterpretation).length] interpCounts;
        size_t[(EnumMembers!AttributeInterpretation).length] interpDimensions;

        foreach(a; attributes) 
        {
            interpCounts[a.interpretation]++;
            interpDimensions[a.interpretation] = attributeDimensions(a.type);
        }

        alias AttributeInterpretation I;
        assert(interpCounts[I.Position] == 1, "Vertex format without a position");
        assert(interpCounts[I.TexCoord] == 0 || interpDimensions[I.TexCoord] == 2,
               "Non-2D texture coordinates are not supported");
        assert(interpCounts[I.Normal] == 0 || interpDimensions[I.Normal] == 3,
               "Normal vertex attribute must be 3D");
        foreach(count; interpCounts)
        {
            assert(count <= 1, "More than one vertex attribute with the same interpretation");
        }
    }
}

/// Mixes in vertex attribute specification into a vertex type.
///
/// Even arguments specify attribute data types. Odd arguments specify 
/// interpretations of their preceding attributes.
mixin template VertexAttributes(Args...)
{
    /// Creates a vertex attribute spec and returns it.
    static VertexAttributeSpec createVertexAttributeSpec_()
    {
        VertexAttribute[] attributes;

        VertexAttribute currentAttribute;
        foreach(i, arg; Args)
        {
            static if(i % 2 == 0)
            {
                currentAttribute.type = attributeType!arg;
            }
            else
            {
                currentAttribute.interpretation = arg;
                attributes ~= currentAttribute;
            }
        }

        auto result = VertexAttributeSpec(attributes);
        result.validate();
        return result;
    }

    /// Mixed in attribute specification.
    static const vertexAttributeSpec_ = createVertexAttributeSpec_();
}

package:

// Get the number of dimensions of a vertex attribute type.
size_t attributeDimensions(const AttributeType type) @safe pure nothrow
{
    final switch(type)
    {
        case AttributeType.vec4: return 4;
        case AttributeType.vec3: return 3;
        case AttributeType.vec2: return 2;
    }
}

// Get the size of single element of a vertex attribute in bytes.
size_t attributeSize(const AttributeType type) @safe pure nothrow
{
    final switch(type)
    {
        case AttributeType.vec4: return vec4.sizeof;
        case AttributeType.vec3: return vec3.sizeof;
        case AttributeType.vec2: return vec2.sizeof;
    }
}

// Convert a D vertex attribute type into AttributeType.
template attributeType(T)
{
    static if(is(T == vec4))     {enum attributeType = AttributeType.vec4;}
    else static if(is(T == vec3)){enum attributeType = AttributeType.vec3;}
    else static if(is(T == vec2)){enum attributeType = AttributeType.vec2;}
    else static assert(false, "Not a vertex attribute type: " ~ T.stringof);
}

private:

// Used to test if the VertexAttributes mixin compiles.
struct TestVertex
{
    vec3 Position;
    vec2 TexCoord;

    mixin VertexAttributes!(vec3, AttributeInterpretation.Position,
                            vec2, AttributeInterpretation.TexCoord);
}
