/*
Copyright (c) 2019-2020 Timur Gafarov

Boost Software License - Version 1.0 - August 17th, 2003
Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

module dagon.render.deferred.geometrypass;

import std.stdio;

import dlib.core.memory;
import dlib.core.ownership;
import dlib.image.color;
import dlib.geometry.frustum;

import dagon.core.bindings;
import dagon.graphics.entity;
import dagon.graphics.terrain;
import dagon.graphics.particles;
import dagon.graphics.shader;
import dagon.render.pipeline;
import dagon.render.pass;
import dagon.render.gbuffer;
import dagon.render.shaders.geometry;
import dagon.render.shaders.terrain;

class DeferredGeometryPass: RenderPass
{
    GBuffer gbuffer;
    GeometryShader geometryShader;
    TerrainShader terrainShader;
    uint renderedEntities = 0;

    this(RenderPipeline pipeline, GBuffer gbuffer, EntityGroup group = null)
    {
        super(pipeline, group);
        this.gbuffer = gbuffer;
        geometryShader = New!GeometryShader(this);
        terrainShader = New!TerrainShader(this);
    }
    
    override void render()
    {
        renderedEntities = 0;
        if (group && gbuffer)
        {
            gbuffer.bind();

            glScissor(0, 0, gbuffer.width, gbuffer.height);
            glViewport(0, 0, gbuffer.width, gbuffer.height);

            geometryShader.bind();
            foreach(entity; group)
            {
                if (entity.visible && entity.drawable)
                {
                    if (!entityIsTerrain(entity) && !entityIsParticleSystem(entity))
                    {
                        auto bb = entity.boundingBox();
                        if (state.frustum.intersectsAABB(bb))
                        {
                            renderEntity(entity, geometryShader);
                            renderedEntities++;
                        }
                    }
                }
            }
            geometryShader.unbind();

            terrainShader.bind();
            foreach(entity; group)
            {
                if (entity.visible && entity.drawable)
                {
                    if (entityIsTerrain(entity))
                    {
                        auto bb = entity.boundingBox();
                        if (state.frustum.intersectsAABB(bb))
                        {
                            renderEntity(entity, terrainShader);
                            renderedEntities++;
                        }
                    }
                }
            }
            terrainShader.unbind();

            gbuffer.unbind();
        }
    }
}
