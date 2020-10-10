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

module dagon.render.deferred.environmentpass;

import std.stdio;

import dlib.core.memory;
import dlib.core.ownership;
import dlib.image.color;

import dagon.core.bindings;
import dagon.graphics.screensurface;
import dagon.render.pipeline;
import dagon.render.pass;
import dagon.render.framebuffer;
import dagon.render.gbuffer;
import dagon.render.shaders.environment;

class DeferredEnvironmentPass: RenderPass
{
    GBuffer gbuffer;
    ScreenSurface screenSurface;
    EnvironmentShader environmentShader;
    Framebuffer outputBuffer;
    Framebuffer occlusionBuffer;

    this(RenderPipeline pipeline, GBuffer gbuffer)
    {
        super(pipeline);
        this.gbuffer = gbuffer;
        screenSurface = New!ScreenSurface(this);
        environmentShader = New!EnvironmentShader(this);
    }

    override void render()
    {
        if (outputBuffer && gbuffer)
        {
            outputBuffer.bind();

            state.colorTexture = gbuffer.colorTexture;
            state.depthTexture = gbuffer.depthTexture;
            state.normalTexture = gbuffer.normalTexture;
            state.pbrTexture = gbuffer.pbrTexture;
            if (occlusionBuffer)
                state.occlusionTexture = occlusionBuffer.colorTexture;
            else
                state.occlusionTexture = 0;

            glScissor(0, 0, outputBuffer.width, outputBuffer.height);
            glViewport(0, 0, outputBuffer.width, outputBuffer.height);

            glEnable(GL_BLEND);
            glBlendFunc(GL_SRC_ALPHA, GL_ONE);

            environmentShader.bind();
            environmentShader.bindParameters(&state);
            screenSurface.render(&state);
            environmentShader.unbindParameters(&state);
            environmentShader.unbind();

            glDisable(GL_BLEND);

            outputBuffer.unbind();
        }
    }
}
