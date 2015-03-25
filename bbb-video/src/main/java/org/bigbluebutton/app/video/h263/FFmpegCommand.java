package org.bigbluebutton.app.video.h263;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.HashMap;
import java.util.Iterator;

public class FFmpegCommand {
    private HashMap args;
    private HashMap x264Params;

    private String[] command;
    
    private String ffmpegPath;
    private String input;
    private String output;

    public FFmpegCommand() {
        this.args = new HashMap();
        this.x264Params = new HashMap();

        this.ffmpegPath = null;
    }

    public String[] getFFmpegCommand(boolean shouldBuild) {
        if(shouldBuild)
            buildFFmpegCommand();
        
        return this.command;
    }

    public void buildFFmpegCommand() {
        List comm = new ArrayList<String>();

        if(this.ffmpegPath == null)
            this.ffmpegPath = "/usr/local/bin/ffmpeg";

        comm.add(this.ffmpegPath);

        comm.add("-i");
        comm.add(input);

        Iterator argsIter = this.args.entrySet().iterator();
        while (argsIter.hasNext()) {
            Map.Entry pairs = (Map.Entry)argsIter.next();
            comm.add(pairs.getKey());
            comm.add(pairs.getValue());
        }

        if(!x264Params.isEmpty()) {
            comm.add("-x264-params");
            String params = "";
            Iterator x264Iter = this.x264Params.entrySet().iterator();
            while (x264Iter.hasNext()) {
                Map.Entry pairs = (Map.Entry)x264Iter.next();
                String argValue = pairs.getKey() + "=" + pairs.getValue();
                params += argValue;
                // x264-params are separated by ':'
                params += ":";
            }
            // Remove trailing ':'
            params.replaceAll(":+$", "");
            comm.add(params);
        }

        comm.add(this.output);

        this.command = new String[comm.size()];
        comm.toArray(this.command);
    }

    public void setFFmpegPath(String arg) {
        this.ffmpegPath = arg;
    }

    public void setInput(String arg) {
        this.input = arg;
    }

    public void setOutput(String arg) {
        this.output = arg;
    }

    public void setCodec(String arg) {
        this.args.put("-vcodec", arg);
    }

    public void setLevel(String arg) {
        this.args.put("-level", arg);
    }

    public void setPreset(String arg) {
        this.args.put("-preset", arg);
    }

    public void setProfile(String arg) {
        this.args.put("-profile:v", arg);
    }

    public void setFormat(String arg) {
        this.args.put("-f", arg);
    }

    public void setPayloadType(String arg) {
        this.args.put("-payload_type", arg);
    }

    public void setLoglevel(String arg) {
        this.args.put("-loglevel", arg);
    }

    public void setSliceMaxSize(String arg) {
        this.x264Params.put("slice-max-size", arg);
    }

    public void setMaxKeyFrameInterval(String arg) {
        this.x264Params.put("keyint", arg);
    }
    
    public void setResolution(String arg) {
        this.args.put("-s", arg);
    }
}