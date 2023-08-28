package com.ryanheise.audioservice;

import java.util.Objects;

public class MediaControl {
    public final String icon;
    public final String label;
    public final long actionCode;
    public final CustomMediaAction customAction;

    public MediaControl(String icon, String label, long actionCode, CustomMediaAction customAction) {
        this.icon = icon;
        this.label = label;
        this.actionCode = actionCode;
        this.customAction = customAction;
    }

    @Override
    public boolean equals(Object other) {
        if (other instanceof MediaControl) {
            MediaControl otherControl = (MediaControl)other;
            return icon.equals(otherControl.icon) && label.equals(otherControl.label) && actionCode == otherControl.actionCode && Objects.equals(customAction, otherControl.customAction);
        } else {
            return false;
        }
    }
}
