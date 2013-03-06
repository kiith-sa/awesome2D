//          Copyright Ferdinand Majerech 2013.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


/// Isometric (really dimetric) map with multiple height levels.
module demo.map;


import std.algorithm;
import std.math;
import std.stdio;

import gl3n.linalg;
import dgamevfs._;

import demo.camera2d;
import demo.sprite;
import demo.tileshape;
import containers.vector;
import math.math;
import memory.memory;
import util.yaml;
import video.renderer;


// Single cell of the map.
//
// May be composed of multiple layers (each represented by a separate tile).
// This can be used to create hills, bridges, and so on.
private struct Cell
{
private:
    // Index to the map's layerIndices_ array where the first layer (layer 0) index is stored.
    // 
    // If there are any more layer indices, they are stored immediately after.
    uint layerIndicesStart_;
    // Number of layers in this cell (i.e. number of indices in the map's layerIndices_ array).
    ushort layerCount_;

public:
    // Get an array of indices pointing to the layers (tiles) of this cell, 
    // starting at layer 0.
    //
    // The indices point to the tiles_ array of the map.
    //
    // Params:  map = Map containing the layer indices.
    // 
    // Returns: Slice of the map's layerIndices_ array containing this cell's layer indices.
    const (ushort[]) layerIndices(Map map) @safe pure const nothrow
    {
        return map.layerIndices_[layerIndicesStart_ .. layerIndicesStart_ + layerCount_];
    }

    // Get the number of layers in this cell.
    @property ushort layerCount() @safe const pure nothrow {return layerCount_;}

    // Return a pointer to the tile at specified layer, or null if there is no tile there.
    const (Tile*) tileAtLayer(const ushort layerIndex, Map map) @safe pure const nothrow
    {
        const layers = layerIndices(map);
        if(layers.length <= layerIndex || layers[layerIndex] == ushort.max)
        {
            return null;
        }
        return &(map.tiles_[layers[layerIndex]]);
    }

    // Does the cell of specified map have ground at specified layer?
    //
    // If the tile shape in the layer is flat, true is returned as long
    // as there is no tile in the above layer.
    bool hasGroundAtLayer(ushort layerIndex, Map map) @safe pure const nothrow
    {
        const(Tile*) layerTile = tileAtLayer(layerIndex, map);
        // When empty (air, layer index 65535)
        if(layerTile is null){return false;}

        if(layerTile.shape == TileShape.Flat)
        {
            // Only if air is directly above.
            return tileAtLayer(layerIndex, map) is null;
        }

        return true;
    }

    // Get the lower bound of number of bytes taken by this struct in RAM (not VRAM).
    @property size_t memoryBytes() @safe pure const nothrow
    {
        return this.sizeof;
    }
}

// 2D tile, used as one layer of a cell.
private struct Tile
{
    // Sprite used to draw the tile. null when not loaded or if loading failed.
    Sprite* sprite;
    // 3D shape of the tile (differentiating between various slopes, flat, etc.).
    TileShape shape;
    // Name of the tile's VFS directory (storing image files and a sprite.yaml metadata file).
    string name;

    // Get the lower bound of number of bytes taken by this struct in RAM (not VRAM).
    @property size_t memoryBytes() @safe const
    {
        return this.sizeof + (sprite is null ? 0 : sprite.memoryBytes) + name.length;
    }
}

/// Isometric map made of 128x64x32 pixel tiles, with 30 degree vertical angle.
///
/// Must be destroyed manually by destroy() to clean up manually allocated memory.
///
///
/// The map cells are multi-layered, allowing for height variations, slopes, bridges, and 
/// so on. The map assumes vertical view angle of 30 degrees. Tile should be 128 x 64 pixels,
/// with 32 pixels for the Z axis of a single layer.
class Map
{
private:
    alias containers.vector.Vector Vector;
    // Cells of the map. Each vector in the cells_ vector is a row of the map.
    Vector!(Vector!Cell) cells_;
    // Indices to tiles (in tiles_) representing layers of each cell. 
    //
    // ushort.max means the layer is empty (air).
    //
    // The cell's layerIndicesStart_ and layerCount_ members decide which items
    // of this vector are indices of that cell's layers.
    Vector!ushort layerIndices_;

    // Tiles used to draw the map, with metadata (shape, VFS directory).
    Vector!(Tile) tiles_;

    // True if the tiles' sprites have been loaded (whether succesfully or not).
    bool tilesLoaded_ = false;

    // The maximum number of layers in any of the cells.
    ushort maxLayerCount_;

    // Size of the map in cells.
    vec2u mapSize_;

public:
    /// Destroy the Map, freeing used memory and destroying loaded sprites.
    ~this()
    {
        if(tilesLoaded_){deleteTiles();}
    }

    /// Load tile sprites used to draw the map.
    ///
    /// Separate from map loading to allow tile loading at a different time.
    void loadTiles(VFSDir gameDir, Renderer renderer)
    {
        assert(!tilesLoaded_, "Trying to load tiles when they are already loaded");

        // We simply don't draw tiles that failed to load, but we keep track of them.
        uint failedCount = 0;
        foreach(ref tile; tiles_)
        {
            // Load the sprite of each tile - tile name specifies the sprite dir.
            assert(tile.sprite is null, "Sprite of a tile is non-null before loading");
            tile.sprite = loadSprite(renderer, gameDir, tile.name);
            // Fail without crashing.
            if(tile.sprite is null)
            {
                writeln("WARNING: Failed to load tile sprite \"", 
                        tile.name, "\" - will not draw it.");
                ++ failedCount;
            }
        }

        if(failedCount > 0)
        {
            writeln("Failed to load ", failedCount, " out of ", tiles_.length, " tile sprites");
        }

        tilesLoaded_ = true;
    }

    /// Delete tile sprites used to draw the map.
    void deleteTiles()
    {
        assert(tilesLoaded_, "Deleting map tiles when they have not been loaded");
        // Only delete sprites that were actually loaded.
        foreach(ref tile; tiles_) if(tile.sprite !is null)
        {
            free(tile.sprite);
            tile.sprite = null;
        }
        tilesLoaded_ = false;
    }

    /// Draw the map.
    ///
    /// Params:  spriteRenderer = Sprite renderer used to draw tiles.
    ///          camera         = Camera used to determine which tiles of the map to draw.
    void draw(SpriteRenderer spriteRenderer, Camera2D camera)
    {
        spriteRenderer.startDrawing();
        scope(exit){spriteRenderer.stopDrawing();}

        // Draw by layers, bottom-to-top.
        foreach(const ushort layer; 0 .. maxLayerCount_)
        {
            // Z coordinate to draw at.
            const z = tileSize.z * layer;

            // Determine the area of this layer visible for the camera.
            const cameraHalfSize = 
                vec2(camera.size.x, camera.size.y) * 0.5f * (1.0f / camera.zoom);
            const cameraCenter = vec2(camera.center) - vec2(0.0f, layer * tilePixelSize.z);

            // 2D bounds of the part of this layer visible for the camera.
            const cameraMin = cameraCenter - cameraHalfSize;
            const cameraMax = cameraCenter + cameraHalfSize;

            // Layout of the cells:
            // Top row:    X strip (determines world space X position of the cell).
            // Middle row: X and Y index of the cell.
            // Bottom row: Y strip (determines world space Y position of the cell).
            //
            //   /\     /\     /\     /\
            //  /X-3   /X-2   /X-1   /X0\
            // /0,6 \ /1,6 \ /2,6 \ /3,6 \
            // \YS3 / \YS4 / \YS5 / \YS6 / \
            //  \  /X-2\  /X-1\  /X0 \  /X1 \
            //   \/ 0,5 \/ 1,5 \/ 2,5 \/ 2,5 \
            //   /\ YS3 /\ YS4 /\ YS5 /\ YS6 /
            //  /X-2   /X-1   /X0\   /X1\   /
            // /0,4 \ /1,4 \ /2,4 \ /3,4 \ /
            // \YS2 / \YS3 / \YS4 / \YS5 /
            //  \  /X-1\  /X0 \  /X1 \  /
            //   \/ 0,3 \/ 1,3 \/ 2,3 \/
            //   /\ YS2 /\ YS3 /\ YS4 /\
            //  /X-1   /X0\   /X1\   /X2\
            // /0,2 \ /1,2 \ /2,2 \ /3,2 \
            // \YS1 / \YS2 / \YS3 / \YS4 / \
            //  \  /X0 \  /X1 \  /X2 \  /X3 \
            //   \/ 0,1 \/ 1,1 \/ 2,1 \/ 3,1 \
            //   /\ YS1 /\ YS2 /\ YS3 /\ YS4 /
            //  /X0\   /X1\   /X2\   /X3\   /
            // /0,0 \ /1,0 \ /2,0 \ /3,0 \ /
            // \YS0 / \YS1 / \YS2 / \YS3 /
            //  \  /   \  /   \  /   \  /
            //   \/     \/     \/     \/

            // Y is multiplied by 0.5 as the rows are half-tile-size apart vertically.
            // (See the cell layout above)

            // Extra tiles we draw around the visible area to account for row/column offsets,
            // weird shaped tiles, etc.
            enum border = 2;
            alias tilePixelSize tPS;

            // Extents of the area we draw in cells.
            const cellMin =
                vec2i(max(0, cast(int)(cameraMin.x / tPS.x) - border),
                      max(0, cast(int)(cameraMin.y / (0.5 * tPS.y)) - border));
            const cellMax =
                vec2i(min(mapSize_.x, cast(int)(cameraMax.x / tPS.x) + border),
                      min(mapSize_.y, cast(int)(cameraMax.y / (0.5 * tPS.y)) + border));

            // X and Y positions of cells increase horizontally and vertically, but 
            // world X and Y coordinates increase in SE, NE directions. So for each cell, 
            // we determine its X and Y strips (marked in layout scheme above as X# and 
            // YS#, where # is a number) to position it in world space.

            // X and Y strip of the first cell in the row.
            int startXStrip = -cellMax.y / 2 + cellMin.x;
            int startYStrip = (cellMax.y + 1) / 2 + cellMin.x;
            // Draw rows of visible tiles of the layer from top of the screen to bottom.
            for(int cellY = (cellMax.y - 1); cellY >= cellMin.y; --cellY)
            {
                // Increases on odd rows going down.
                startXStrip += cellY % 2;
                // Decreases on even rows going down.
                startYStrip -= 1 - cellY % 2;
                // X and Y strip of the current cell.
                int xStrip = startXStrip;
                int yStrip = startYStrip;
                const rowOffset =  (cellY % 2) * 0.5 * tileSize.x;
                // Draw the individual tiles within the row.
                foreach(const cellX; cellMin.x .. cellMax.x)
                {
                    ++ xStrip;
                    ++ yStrip;
                    const(Cell*) cell = &cell(cellX, cellY);
                    // The cell doesn't have this layer.
                    if(cell.layerCount <= layer) {continue;}

                    const layerIndex = cell.layerIndices(this)[layer];
                    // Empty layer (air).
                    if(layerIndex == ushort.max){continue;}

                    // World-space X and Y coordinates of the cell.
                    const x = tileSize.x * xStrip;
                    const y = tileSize.y * yStrip;
                    Sprite* tile = tiles_[layerIndex].sprite;
                    // Sprite loading might have failed.
                    if(tile is null){continue;}
                    spriteRenderer.drawSprite(tile, vec3(x, y, z), vec3(0.0f, 0.0f, 0.0f));
                }
            }
        }
    }

    /// Get the width of the map in cells.
    @property uint cellWidth() @safe const pure nothrow {return mapSize_.x;}

    /// Get the height of the map in cells.
    @property uint cellHeight() @safe const pure nothrow {return mapSize_.y;}

    /// Get the lower bound of number of bytes taken by this struct in RAM (not VRAM).
    @property size_t memoryBytes() @trusted const
    {
        alias reduce!"a + b" sum;
        return this.sizeof + 
               sum(tiles_[].map!(t => t.memoryBytes)) +
               layerIndices_.length * ushort.sizeof  +
               cells_.length * Vector!Cell.sizeof    +
               sum(cells_[].map!(row => sum(row[].map!(c => c.memoryBytes))));
    }

    /// Get a range of GroundDescriptions describing all ground levels on 
    /// specified world space coordinates (heights and normals on all tiles in the cell
    /// that units can stand on).
    ///
    /// The range starts at the lowest ground level, going up.
    /// Most of the time, this range will have just one element, but on bridges or 
    /// multi-layered maps, it could be more.
    ///
    /// All ground descriptions in the range will be passable.
    ///
    /// Params:  worldX = World space X coordinate to get ground levels at.
    ///          worldY = World space Y coordinate to get ground levels at.
    auto groundLevelsAtWorldCoords(const vec2 worldCoords) @safe
    {
        // Range of GroundDescriptions describing ground levels on specified world coordinates.
        //
        // POSSIBLE OPTIMIZATION: Remember the cell at the world coords in a data member.
        static struct HeightRange
        {
            // World space coordinates.
            vec2 worldCoords_;
            // Map we're working with.
            Map map_;
            // Current layer in the cell on the world space coordinates.
            ushort currentLayer_ = 0;

            // Get the current ground level.
            GroundDescription front() @safe
            {
                assert(!empty, "HeightRange front called when empty");

                // Empty ensures this is not null.
                Cell* cell  = map_.cellAt(worldCoords_);
                const tile  = cell.tileAtLayer(currentLayer_, map_);
                assert(tile !is null, "Tile at the current layer is null "
                                      "even though the HeightRange is not empty");

                const shape = tile.shape;
                const baseHeight = tileSize.z * currentLayer_;
                // Flat tiles have a constant height.
                if(shape == TileShape.Flat)
                {
                    return GroundDescription(normalUp, baseHeight + tileSize.z);
                }

                const tileCoords = worldCoordsToCell(worldCoords);

                // Get height in the tile for the tile coords.
                auto result = tileHeightFunctions[cast(ubyte)shape](tileCoords);
                result.height += baseHeight;
                return result;
            }

            // Move to the next ground level.
            void popFront() @safe
            {
                assert(!empty, "HeightRange popFront called when empty");
                // Empty ensures this is not null.
                Cell* cell = map_.cellAt(worldCoords);
                do
                {
                    ++currentLayer_;
                }
                while(!cell.hasGroundAtLayer(currentLayer_, map_));
            }

            // Are there no more ground levels?
            @property bool empty() @safe
            {
                Cell* cell = map_.cellAt(worldCoords);
                // No ground levels outside of the map.
                if(cell is null){return true;}
                foreach(ushort layer; currentLayer_ .. cell.layerCount)
                {
                    // POSSIBLE OPTIMIZATION: We could cache the layer index here for popFront.
                    if(cell.hasGroundAtLayer(layer, map_))
                    {
                        return false;
                    }
                }
                return true;
            }
        }

        return HeightRange(worldCoords, this);
    }

    /// Get the ground description near to specified ground position.
    ///
    /// Useful for unit movement, to determine how high/low the terrain near a unit is.
    ///
    /// Should only be used for very short distances between reference X,Y coords and 
    /// traget, e.g. unit movement per frame. At the moment, this just gets the closest 
    /// ground height at target coordinates, so it won't be useful at all with larger 
    /// distances (especially distances greater than one cell);
    GroundDescription neighborGround
        (const vec3 referenceGroundPos, const vec2 targetXY)
    {
        auto levels = groundLevelsAtWorldCoords(targetXY);
        if(levels.empty)
        {
            return GroundDescription(vec3.init, float.init, true);
        }
        float closestHeightDifference = float.max;
        GroundDescription closestGround;
        foreach(level; levels) 
        {
            const heightDifference = abs(level.height - referenceGroundPos.z);
            if(heightDifference < closestHeightDifference)
            {
                closestGround           = level;
                closestHeightDifference = heightDifference;
            }
        }

        return closestGround;
    }

private:
    /// Access the cell at specified cell coordinates. 
    ///
    /// This should be used to access cells to allow changes in cell storage.
    ref Cell cell(const uint x, const uint y) @trusted 
    {
        return cells_[y][x];
    }

    /// Access the cell at specified world space coordinates.
    Cell* cellAt(const float worldCoords) @safe
    {
        const cellCoords = worldToCell(worldCoords);
        if(cellCoords.x < 0 || cellCoords.x >= mapSize_.x ||
           cellCoords.y < 0 || cellCoords.y >= mapSize_y)
        {
            return null;
        }
        return &cell(cellCoords.x, cellCoords.y);
    }

    /// Get the cell coordinates of the cell on specified world space coordinates.
    vec2i worldToCell(const float worldX, const float worldY) @safe pure nothrow const
    {
        // We add half tile sizes as the tiles' positions are in the tiles' centers,
        // not the W corner.
        const xStrip = cast(int)floor((tileSize.x * 0.5 + worldX) / tileSize.x); 
        const yStrip = cast(int)floor((tileSize.y * 0.5 + worldY) / tileSize.y); 
        return vec2i(yStrip - xStrip, (yStrip + xStrip) / 2);
    }

    /// Construct a map with specified size.
    ///
    /// This will construct an empty map with no tiles anywhere.
    this(const vec2u mapSize)
    {
        mapSize_ = mapSize;
        cells_.length = mapSize.y;
        foreach(y; 0 .. mapSize.y)
        {
            cells_[y].length = mapSize.x;
        }
        maxLayerCount_ = 0;
    }
}

/// Load a map from a file.
///
/// Params:  gameDir = Game data directory; contains the map file.
///          mapName = Filename of the map in gameDir.
///
/// Returns: Loaded map on success, null on failure.
Map loadMap(VFSDir gameDir, string mapName)
{
    try
    {
        auto mapYAML = loadYAML(gameDir.file(mapName));

        // Load map metadata.
        auto meta = mapYAML["meta"];
        if(meta["formatVersion"].as!int != 0)
        {
            writeln("Error loading map \"", mapName, "\": Unknown format version");
            return null;
        }
        const cellWidth  = meta["width"].as!uint;
        const cellHeight = meta["height"].as!uint;

        Map map = new Map(vec2u(cellWidth, cellHeight));
        scope(failure){destroy(map);}

        // Load tiles.
        foreach(string tileName; mapYAML["tiles"])
        {
            static TileShape tileShape(string tileName, string mapName)
            {
                if(tileName.endsWith("flat"))               {return TileShape.Flat;}
                else if(tileName.endsWith("slope-ne"))      {return TileShape.SlopeNE;}
                else if(tileName.endsWith("slope-se"))      {return TileShape.SlopeSE;}
                else if(tileName.endsWith("slope-nw"))      {return TileShape.SlopeNW;}
                else if(tileName.endsWith("slope-sw"))      {return TileShape.SlopeSW;}
                else if(tileName.endsWith("cliff-n"))       {return TileShape.CliffN;}
                else if(tileName.endsWith("cliff-s"))       {return TileShape.CliffS;}
                else if(tileName.endsWith("cliff-w"))       {return TileShape.CliffW;}
                else if(tileName.endsWith("cliff-e"))       {return TileShape.CliffE;}
                else if(tileName.endsWith("slope-n-top"))   {return TileShape.SlopeNTop;}
                else if(tileName.endsWith("slope-s-top"))   {return TileShape.SlopeSTop;}
                else if(tileName.endsWith("slope-w-right")) {return TileShape.SlopeWRight;}
                else if(tileName.endsWith("slope-e-right")) {return TileShape.SlopeERight;}
                else if(tileName.endsWith("slope-n-bottom")){return TileShape.SlopeNBottom;}
                else if(tileName.endsWith("slope-s-bottom")){return TileShape.SlopeSBottom;}
                else if(tileName.endsWith("slope-w-left"))  {return TileShape.SlopeWLeft;}
                else if(tileName.endsWith("slope-e-left"))  {return TileShape.SlopeELeft;}
                else
                {
                    writeln("WARNING: Can't determine tile shape from directory name \"", 
                            tileName, "\" while loading map \"", mapName, "\". Assuming flat.");
                    return TileShape.Flat;
                }
            }
            map.tiles_ ~= Tile(null, tileShape(tileName, mapName), tileName);
        }

        // Load the map cells.
        map.maxLayerCount_ = 0;
        uint y = 0;
        foreach(ref YAMLNode row; mapYAML["rows"])
        {
            uint x = 0;
            foreach(ref YAMLNode cell; row)
            {
                auto c = &(map.cell(x, y));
                c.layerIndicesStart_ = cast(uint)map.layerIndices_.length;
                if(cell.length > ushort.max)
                {
                    writeln("WARNING: Cell [", x, ", ", y, "] has more than 65535 layers ",
                            "while loading map \"", mapName, "\": ignoring layers above 65535");
                }

                c.layerCount_ = cast(ushort)min(cell.length, ushort.max);
                map.maxLayerCount_ = max(c.layerCount_, map.maxLayerCount_);
                foreach(ushort tileIndex; cell)
                {
                    map.layerIndices_ ~= tileIndex;
                }
                ++x;
            }
            ++y;
        }

        return map;
    }
    catch(VFSException e)
    {
        writeln("Filesystem error loading map \"", mapName, "\": ", e.msg);
        return null;
    } 
    catch(YAMLException e)
    {
        writeln("YAML error loading map \"", mapName, "\": ", e.msg);
        return null;
    }
}

/// Generate a dummy map used for testing.
///
/// Returns: Generated test map.
Map generateTestMap()
{
    Map map = new Map(vec2u(64, 64));

    with(map)
    {
        // 2 different tiles to differentiate cells.
        tiles_ ~= Tile(null, TileShape.Flat, "sprites/test/tiles/grass01");
        tiles_ ~= Tile(null, TileShape.Flat, "sprites/test/tiles/bridge01");
        // Initialize each cell.
        foreach(y; 0 .. cellWidth)
        {
            foreach(x; 0 .. cellHeight)
            {
                auto c = &cell(x, y);
                c.layerIndicesStart_ = cast(uint)layerIndices_.length;
                c.layerCount_ = 1;
                // Simple pattern so we see the cells are not the same.
                if((x + y) % 2 == 0) 
                {
                    layerIndices_ ~= cast(ushort)0;
                    // Add a second layer to some tiles to test layers.
                    if((x + y) % 8 == 0)
                    {
                        ++ c.layerCount_;
                        layerIndices_ ~= cast(ushort)1;
                    }
                }
                else {layerIndices_ ~= cast(ushort)1;}
            }
        }
        maxLayerCount_ = 2;
    }

    return map;
}
