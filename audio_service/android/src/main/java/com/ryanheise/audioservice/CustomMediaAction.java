package com.ryanheise.audioservice;

import java.util.Map;
import java.util.Objects;

public class CustomMediaAction {
    public final String name;
    public final Map<?, ?> extras;

    public CustomMediaAction(String name, Map<?, ?> extras) {
        this.name = name;
        this.extras = extras;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        CustomMediaAction that = (CustomMediaAction) o;
        return name.equals(that.name) && Objects.equals(extras, that.extras);
    }

    @Override
    public int hashCode() {
        return Objects.hash(name, extras);
    }
}
