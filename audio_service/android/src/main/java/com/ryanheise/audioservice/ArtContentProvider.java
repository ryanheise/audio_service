package com.ryanheise.audioservice;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.CancellationSignal;
import android.os.ParcelFileDescriptor;
import android.util.Log;
import android.util.SparseArray;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.io.File;
import java.io.FileNotFoundException;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

import io.flutter.plugin.common.MethodChannel;

public class ArtContentProvider extends ContentProvider {
    @Override
    public boolean onCreate() {
        return true;
    }

    private ExecutorService executorService = Executors.newCachedThreadPool();

    private int id = 0;
    private synchronized int getRequestId() {
        final int requestId = id;
        id++;
        if (id > 100000) {
            id = 0;
        }
        return requestId;
    }

    private static final SparseArray<MethodChannel.Result> results = new SparseArray<>();

    /**
     * Successfully end art path request task.
     */
    static void successPathRequest(int requestId, String path) {
        synchronized (results) {
            Log.w("ArtContentProvider", "success " + requestId);
            MethodChannel.Result result = results.get(requestId);
            result.success(path);
        }
    }

    /**
     * End art path request task with null path due to error.
     */
    static void terminatePathRequest(int requestId) {
        synchronized (results) {
            Log.w("ArtContentProvider", "error " + requestId);
            MethodChannel.Result result = results.get(requestId);
            result.error(null, null, null);
        }
    }

    class Task implements Callable<String> {
        Task(Uri uri) {
            this.uri = uri;
        }

        Uri uri;
        String path;
        boolean responded = false;

        @Override
        public String call() throws Exception {
            final int requestId = getRequestId();
            Log.w("ArtContentProvider", "start " + requestId);
            MethodChannel.Result result = new MethodChannel.Result() {
                void end() {
                    responded = true;
                    synchronized (Task.this) {
                        Task.this.notify();
                    }
                }

                @Override
                public void success(@Nullable Object result) {
                    path = (String) result;
                    results.remove(requestId);
                    end();
                }

                @Override
                public void error(String errorCode, @Nullable String errorMessage, @Nullable Object errorDetails) {
                    end();
                }

                @Override
                public void notImplemented() {
                    end();
                }
            };

            synchronized (results) {
                results.put(requestId, result);
            }

            AudioServicePlugin.getArtFilePath(requestId, uri);

            synchronized (Task.this) {
                while (!responded) {
                    Task.this.wait();
                }
            }
            return path;
        }
    }

    @Nullable
    @Override
    public ParcelFileDescriptor openFile(@NonNull Uri uri, @NonNull String mode) throws FileNotFoundException {
        Task task = new Task(uri);
        Future<String> future = executorService.submit(task);
//        cancellationSignal.setOnCancelListener(() -> {
//            task.lock.notify();
//        });
        String path = null;
        try {
            path = future.get();
        } catch (ExecutionException e) {
            e.printStackTrace();
        } catch (InterruptedException e) {
            e.printStackTrace();
        }
        File file;
        if (path != null) {
            file = new File(path);
        } else {
            throw new FileNotFoundException(path);
        }
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY);
    }

    @Nullable
    @Override
    public Cursor query(@NonNull Uri uri, @Nullable String[] projection, @Nullable String selection, @Nullable String[] selectionArgs, @Nullable String sortOrder) {
        return null;
    }

    @Nullable
    @Override
    public String getType(@NonNull Uri uri) {
        return null;
    }

    @Nullable
    @Override
    public Uri insert(@NonNull Uri uri, @Nullable ContentValues values) {
        return null;
    }

    @Override
    public int delete(@NonNull Uri uri, @Nullable String selection, @Nullable String[] selectionArgs) {
        return 0;
    }

    @Override
    public int update(@NonNull Uri uri, @Nullable ContentValues values, @Nullable String selection, @Nullable String[] selectionArgs) {
        return 0;
    }
}
